#include <errno.h>
#include <fcntl.h>
#include <linux/videodev2.h>
#include <sys/ioctl.h>
#include <sys/mman.h>
#include <unistd.h>

#include <cstring>
#include <iostream>
#include <string>
#include <vector>

namespace {

int xioctl(int fd, unsigned long request, void *arg)
{
    int r;
    do {
        r = ioctl(fd, request, arg);
    } while (r == -1 && errno == EINTR);
    return r;
}

uint32_t fourcc_from_string(const std::string &s)
{
    char c[4] = {' ', ' ', ' ', ' '};
    for (size_t i = 0; i < s.size() && i < 4; ++i) {
        c[i] = s[i];
    }
    return v4l2_fourcc(c[0], c[1], c[2], c[3]);
}

std::string fourcc_to_string(uint32_t f)
{
    std::string s;
    s.push_back(static_cast<char>(f & 0xff));
    s.push_back(static_cast<char>((f >> 8) & 0xff));
    s.push_back(static_cast<char>((f >> 16) & 0xff));
    s.push_back(static_cast<char>((f >> 24) & 0xff));
    return s;
}

struct Buffer {
    void *start = nullptr;
    size_t length = 0;
};

bool is_capture_device(const v4l2_capability &cap)
{
    const uint32_t caps = (cap.capabilities & V4L2_CAP_DEVICE_CAPS) ? cap.device_caps : cap.capabilities;
    return (caps & V4L2_CAP_VIDEO_CAPTURE) != 0;
}

void print_intervals(int fd, uint32_t pixelformat, uint32_t width, uint32_t height)
{
    for (uint32_t k = 0;; ++k) {
        v4l2_frmivalenum interval {};
        interval.index = k;
        interval.pixel_format = pixelformat;
        interval.width = width;
        interval.height = height;
        if (xioctl(fd, VIDIOC_ENUM_FRAMEINTERVALS, &interval) < 0) {
            break;
        }
        if (interval.type == V4L2_FRMIVAL_TYPE_DISCRETE && interval.discrete.numerator != 0) {
            double fps = static_cast<double>(interval.discrete.denominator) /
                         static_cast<double>(interval.discrete.numerator);
            std::cout << "      @" << fps << "Hz" << std::endl;
        } else if (interval.type == V4L2_FRMIVAL_TYPE_STEPWISE) {
            std::cout << "      interval stepwise" << std::endl;
        } else if (interval.type == V4L2_FRMIVAL_TYPE_CONTINUOUS) {
            std::cout << "      interval continuous" << std::endl;
        }
    }
}

int print_device_info(const char *device)
{
    int fd = open(device, O_RDWR | O_NONBLOCK, 0);
    if (fd < 0) {
        std::cerr << "open(" << device << ") failed: " << strerror(errno) << std::endl;
        return 1;
    }

    v4l2_capability cap {};
    if (xioctl(fd, VIDIOC_QUERYCAP, &cap) < 0) {
        std::cerr << "VIDIOC_QUERYCAP failed: " << strerror(errno) << std::endl;
        close(fd);
        return 1;
    }

    std::cout << "device: " << device << std::endl;
    std::cout << "driver: " << cap.driver << " card: " << cap.card << " bus: " << cap.bus_info << std::endl;
    std::cout << "capabilities: 0x" << std::hex << cap.capabilities << " device_caps: 0x"
              << cap.device_caps << std::dec << std::endl;
    std::cout << "is_metadata_like: " << (is_capture_device(cap) ? "false" : "true") << std::endl;

    bool has_formats = false;
    std::cout << "formats:" << std::endl;
    for (uint32_t i = 0;; ++i) {
        v4l2_fmtdesc fmt {};
        fmt.index = i;
        fmt.type = V4L2_BUF_TYPE_VIDEO_CAPTURE;
        if (xioctl(fd, VIDIOC_ENUM_FMT, &fmt) < 0) {
            break;
        }
        has_formats = true;
        std::cout << "  " << i << ": " << fourcc_to_string(fmt.pixelformat)
                  << " " << fmt.description << std::endl;
        for (uint32_t j = 0;; ++j) {
            v4l2_frmsizeenum size {};
            size.index = j;
            size.pixel_format = fmt.pixelformat;
            if (xioctl(fd, VIDIOC_ENUM_FRAMESIZES, &size) < 0) {
                break;
            }
            if (size.type == V4L2_FRMSIZE_TYPE_DISCRETE) {
                std::cout << "    " << size.discrete.width << "x" << size.discrete.height << std::endl;
                print_intervals(fd, fmt.pixelformat, size.discrete.width, size.discrete.height);
            } else if (size.type == V4L2_FRMSIZE_TYPE_STEPWISE) {
                std::cout << "    size stepwise" << std::endl;
            } else if (size.type == V4L2_FRMSIZE_TYPE_CONTINUOUS) {
                std::cout << "    size continuous" << std::endl;
            }
        }
    }
    if (!has_formats) {
        std::cout << "  (none)" << std::endl;
    }
    close(fd);
    return 0;
}

}  // namespace

int main(int argc, char **argv)
{
    if (argc > 1 && std::string(argv[1]) == "--list") {
        const char *device = argc > 2 ? argv[2] : "/dev/video0";
        return print_device_info(device);
    }

    const char *device = argc > 1 ? argv[1] : "/dev/video0";
    const int width = argc > 2 ? std::atoi(argv[2]) : 640;
    const int height = argc > 3 ? std::atoi(argv[3]) : 480;
    const int fps = argc > 4 ? std::atoi(argv[4]) : 15;
    const int frame_count = argc > 5 ? std::atoi(argv[5]) : 100;
    const std::string fourcc_arg = argc > 6 ? argv[6] : "Z16";
    const uint32_t pixfmt = fourcc_from_string(fourcc_arg);

    int fd = open(device, O_RDWR | O_NONBLOCK, 0);
    if (fd < 0) {
        std::cerr << "open(" << device << ") failed: " << strerror(errno) << std::endl;
        return 1;
    }

    v4l2_capability cap {};
    if (xioctl(fd, VIDIOC_QUERYCAP, &cap) < 0) {
        std::cerr << "VIDIOC_QUERYCAP failed: " << strerror(errno) << std::endl;
        close(fd);
        return 1;
    }

    std::cout << "device: " << device << std::endl;
    std::cout << "driver: " << cap.driver << " card: " << cap.card << " bus: " << cap.bus_info << std::endl;
    std::cout << "capabilities: 0x" << std::hex << cap.capabilities << " device_caps: 0x"
              << cap.device_caps << std::dec << std::endl;

    std::cout << "formats:" << std::endl;
    for (uint32_t i = 0;; ++i) {
        v4l2_fmtdesc fmt {};
        fmt.index = i;
        fmt.type = V4L2_BUF_TYPE_VIDEO_CAPTURE;
        if (xioctl(fd, VIDIOC_ENUM_FMT, &fmt) < 0) {
            break;
        }
        std::cout << "  " << i << ": " << fourcc_to_string(fmt.pixelformat)
                  << " " << fmt.description << std::endl;
    }

    v4l2_format fmt {};
    fmt.type = V4L2_BUF_TYPE_VIDEO_CAPTURE;
    fmt.fmt.pix.width = width;
    fmt.fmt.pix.height = height;
    fmt.fmt.pix.pixelformat = pixfmt;
    fmt.fmt.pix.field = V4L2_FIELD_NONE;

    std::cout << "set fmt: " << width << "x" << height << " " << fourcc_to_string(pixfmt) << std::endl;
    if (xioctl(fd, VIDIOC_S_FMT, &fmt) < 0) {
        std::cerr << "VIDIOC_S_FMT failed: errno=" << errno << " " << strerror(errno) << std::endl;
        close(fd);
        return 2;
    }
    std::cout << "actual fmt: " << fmt.fmt.pix.width << "x" << fmt.fmt.pix.height
              << " " << fourcc_to_string(fmt.fmt.pix.pixelformat)
              << " bytesperline=" << fmt.fmt.pix.bytesperline
              << " sizeimage=" << fmt.fmt.pix.sizeimage << std::endl;
    if (fmt.fmt.pix.pixelformat != pixfmt || static_cast<int>(fmt.fmt.pix.width) != width ||
        static_cast<int>(fmt.fmt.pix.height) != height) {
        std::cerr << "Requested format was not accepted exactly" << std::endl;
        close(fd);
        return 2;
    }

    v4l2_streamparm parm {};
    parm.type = V4L2_BUF_TYPE_VIDEO_CAPTURE;
    parm.parm.capture.timeperframe.numerator = 1;
    parm.parm.capture.timeperframe.denominator = fps;
    std::cout << "set fps: " << fps << std::endl;
    if (xioctl(fd, VIDIOC_S_PARM, &parm) < 0) {
        std::cerr << "VIDIOC_S_PARM failed: errno=" << errno << " " << strerror(errno) << std::endl;
    }

    v4l2_requestbuffers req {};
    req.count = 4;
    req.type = V4L2_BUF_TYPE_VIDEO_CAPTURE;
    req.memory = V4L2_MEMORY_MMAP;
    if (xioctl(fd, VIDIOC_REQBUFS, &req) < 0) {
        std::cerr << "VIDIOC_REQBUFS failed: errno=" << errno << " " << strerror(errno) << std::endl;
        close(fd);
        return 3;
    }
    if (req.count < 2) {
        std::cerr << "Not enough mmap buffers: " << req.count << std::endl;
        close(fd);
        return 3;
    }

    std::vector<Buffer> buffers(req.count);
    for (uint32_t i = 0; i < req.count; ++i) {
        v4l2_buffer buf {};
        buf.type = V4L2_BUF_TYPE_VIDEO_CAPTURE;
        buf.memory = V4L2_MEMORY_MMAP;
        buf.index = i;
        if (xioctl(fd, VIDIOC_QUERYBUF, &buf) < 0) {
            std::cerr << "VIDIOC_QUERYBUF failed: errno=" << errno << " " << strerror(errno) << std::endl;
            close(fd);
            return 3;
        }
        buffers[i].length = buf.length;
        buffers[i].start = mmap(nullptr, buf.length, PROT_READ | PROT_WRITE, MAP_SHARED, fd, buf.m.offset);
        if (buffers[i].start == MAP_FAILED) {
            std::cerr << "mmap failed: " << strerror(errno) << std::endl;
            close(fd);
            return 3;
        }
        if (xioctl(fd, VIDIOC_QBUF, &buf) < 0) {
            std::cerr << "VIDIOC_QBUF failed: errno=" << errno << " " << strerror(errno) << std::endl;
            close(fd);
            return 3;
        }
    }

    v4l2_buf_type type = V4L2_BUF_TYPE_VIDEO_CAPTURE;
    std::cout << "stream on" << std::endl;
    if (xioctl(fd, VIDIOC_STREAMON, &type) < 0) {
        std::cerr << "VIDIOC_STREAMON failed: errno=" << errno << " " << strerror(errno) << std::endl;
        close(fd);
        return 4;
    }

    int received = 0;
    while (received < frame_count) {
        fd_set fds;
        FD_ZERO(&fds);
        FD_SET(fd, &fds);
        timeval tv {};
        tv.tv_sec = 5;
        int r = select(fd + 1, &fds, nullptr, nullptr, &tv);
        if (r < 0) {
            std::cerr << "select failed: " << strerror(errno) << std::endl;
            break;
        }
        if (r == 0) {
            std::cerr << "select timeout after " << received << " frames" << std::endl;
            break;
        }

        v4l2_buffer buf {};
        buf.type = V4L2_BUF_TYPE_VIDEO_CAPTURE;
        buf.memory = V4L2_MEMORY_MMAP;
        if (xioctl(fd, VIDIOC_DQBUF, &buf) < 0) {
            if (errno == EAGAIN) {
                continue;
            }
            std::cerr << "VIDIOC_DQBUF failed: errno=" << errno << " " << strerror(errno) << std::endl;
            break;
        }
        ++received;
        std::cout << "frame " << received << " bytes=" << buf.bytesused
                  << " seq=" << buf.sequence << std::endl;
        if (xioctl(fd, VIDIOC_QBUF, &buf) < 0) {
            std::cerr << "VIDIOC_QBUF requeue failed: errno=" << errno << " " << strerror(errno) << std::endl;
            break;
        }
    }

    xioctl(fd, VIDIOC_STREAMOFF, &type);
    for (auto &b : buffers) {
        if (b.start && b.start != MAP_FAILED) {
            munmap(b.start, b.length);
        }
    }
    close(fd);

    if (received < frame_count) {
        std::cerr << "only received " << received << "/" << frame_count << " frames" << std::endl;
        return 5;
    }
    std::cout << "v4l2 stream ok" << std::endl;
    return 0;
}
