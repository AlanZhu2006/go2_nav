#include <chrono>
#include <atomic>
#include <iostream>
#include <librealsense2/rs.hpp>
#include <thread>

int main(int argc, char ** argv)
{
    const int width = argc > 1 ? std::atoi(argv[1]) : 424;
    const int height = argc > 2 ? std::atoi(argv[2]) : 240;
    const int fps = argc > 3 ? std::atoi(argv[3]) : 6;
    const int frames = argc > 4 ? std::atoi(argv[4]) : 30;

    try {
        rs2::context context;
        auto devices = context.query_devices();
        std::cout << "devices: " << devices.size() << std::endl;
        if (devices.size() == 0) {
            std::cerr << "No RealSense device found" << std::endl;
            return 2;
        }

        for (auto && device : devices) {
            std::cout << "device: "
                      << device.get_info(RS2_CAMERA_INFO_NAME) << " "
                      << device.get_info(RS2_CAMERA_INFO_SERIAL_NUMBER) << " fw "
                      << device.get_info(RS2_CAMERA_INFO_FIRMWARE_VERSION) << std::endl;
            for (auto && sensor : device.query_sensors()) {
                std::cout << "sensor: " << sensor.get_info(RS2_CAMERA_INFO_NAME) << std::endl;
                for (auto && profile : sensor.get_stream_profiles()) {
                    if (profile.stream_type() != RS2_STREAM_DEPTH) {
                        continue;
                    }
                    auto video = profile.as<rs2::video_stream_profile>();
                    std::cout << "  depth "
                              << video.width() << "x" << video.height()
                              << "@" << video.fps()
                              << " fmt=" << profile.format()
                              << " index=" << profile.stream_index()
                              << std::endl;
                }
            }
        }

        rs2::sensor depth_sensor;
        rs2::stream_profile selected_profile;
        bool found = false;
        for (auto && sensor : devices.front().query_sensors()) {
            if (std::string(sensor.get_info(RS2_CAMERA_INFO_NAME)) != "Stereo Module") {
                continue;
            }
            for (auto && profile : sensor.get_stream_profiles()) {
                if (profile.stream_type() != RS2_STREAM_DEPTH || profile.format() != RS2_FORMAT_Z16) {
                    continue;
                }
                auto video = profile.as<rs2::video_stream_profile>();
                if (video.width() == width && video.height() == height && video.fps() == fps) {
                    depth_sensor = sensor;
                    selected_profile = profile;
                    found = true;
                    break;
                }
            }
        }

        if (!found) {
            std::cerr << "Requested depth profile was not found" << std::endl;
            return 3;
        }

        std::cout << "starting depth sensor " << width << "x" << height << "@" << fps << std::endl;
        std::atomic<int> count{0};
        depth_sensor.open(selected_profile);
        depth_sensor.start([&](rs2::frame frame) {
            auto depth = frame.as<rs2::depth_frame>();
            if (!depth) {
                return;
            }
            int current = ++count;
            std::cout << "frame " << current
                      << " ts=" << depth.get_timestamp()
                      << " size=" << depth.get_width() << "x" << depth.get_height()
                      << std::endl;
        });

        const auto deadline = std::chrono::steady_clock::now() + std::chrono::seconds(10);
        while (count.load() < frames && std::chrono::steady_clock::now() < deadline) {
            std::this_thread::sleep_for(std::chrono::milliseconds(50));
        }
        depth_sensor.stop();
        depth_sensor.close();

        if (count.load() < frames) {
            std::cerr << "Only received " << count.load() << " depth frames" << std::endl;
            return 4;
        }
        std::cout << "depth stream ok" << std::endl;
        return 0;
    } catch (const rs2::error & e) {
        std::cerr << "RealSense error: " << e.what() << std::endl;
        return 1;
    } catch (const std::exception & e) {
        std::cerr << "Error: " << e.what() << std::endl;
        return 1;
    }
}
