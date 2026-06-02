#!/usr/bin/env python3
"""Filter a PCD map for ICP localization."""

from __future__ import annotations

import argparse
from pathlib import Path

import numpy as np
import open3d as o3d


def main() -> int:
    parser = argparse.ArgumentParser(description="Create a filtered PCD for ICP localization")
    parser.add_argument("--input", required=True, help="Input PCD path")
    parser.add_argument("--output", required=True, help="Output PCD path")
    parser.add_argument("--z-min", type=float, default=0.20)
    parser.add_argument("--z-max", type=float, default=1.50)
    parser.add_argument("--voxel", type=float, default=0.05, help="Voxel size after filtering; 0 disables")
    parser.add_argument("--stat-nb", type=int, default=20, help="Statistical outlier neighbor count; 0 disables")
    parser.add_argument("--stat-std", type=float, default=2.0, help="Statistical outlier std ratio")
    args = parser.parse_args()

    input_path = Path(args.input).expanduser()
    output_path = Path(args.output).expanduser()

    pcd = o3d.io.read_point_cloud(str(input_path))
    points = np.asarray(pcd.points)
    if points.size == 0:
        raise RuntimeError(f"No points read from {input_path}")

    mask = (points[:, 2] >= args.z_min) & (points[:, 2] <= args.z_max)
    filtered = pcd.select_by_index(np.flatnonzero(mask).tolist())

    if args.voxel > 0:
        filtered = filtered.voxel_down_sample(args.voxel)

    if args.stat_nb > 0 and len(filtered.points) > args.stat_nb:
        filtered, _ = filtered.remove_statistical_outlier(
            nb_neighbors=args.stat_nb,
            std_ratio=args.stat_std,
        )

    output_path.parent.mkdir(parents=True, exist_ok=True)
    if not o3d.io.write_point_cloud(str(output_path), filtered, write_ascii=False):
        raise RuntimeError(f"Failed to write {output_path}")

    out_points = np.asarray(filtered.points)
    print(f"input:  {input_path}")
    print(f"output: {output_path}")
    print(f"z band: {args.z_min:.3f} .. {args.z_max:.3f}")
    print(f"points: {len(points)} -> {len(out_points)}")
    if len(out_points):
        print(f"min:    {out_points.min(axis=0)}")
        print(f"max:    {out_points.max(axis=0)}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
