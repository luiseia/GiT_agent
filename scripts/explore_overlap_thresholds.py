#!/usr/bin/env python
"""
Overlap Threshold Exploration (v2):
Metric: IoB = intersection(cell, bbox_2d) / area(bbox_2d)
  即：该 cell 与 2D 框的重叠面积，占 2D 框总面积的百分之几。

对于小物体(bbox小): 单个 cell 的 IoB 可能很高(bbox 大部分在一个 cell 里)
对于大物体(bbox大): 单个 cell 的 IoB 较低(bbox 横跨很多 cell)

探索阈值: 0%, 1%, 2%, 5%, 10%, 20%
"""

import sys
import os
import os.path as osp
import numpy as np
import cv2
import pickle
from collections import defaultdict

GIT_ROOT = '/home/UNT/yz0370/projects/GiT'
sys.path.insert(0, GIT_ROOT)

CLASSES = ["car", "truck", "bus", "trailer", "pedestrian", "barrier",
           "traffic_cone", "motorcycle", "construction_vehicle", "bicycle"]
RESIZED_IMG_SIZE = 1120
NUMBER_WIN = 5
GRID_RESOLUTION_PERWIN = (4, 4)
GRID_FINE_W = NUMBER_WIN * GRID_RESOLUTION_PERWIN[1]  # 20
GRID_FINE_H = NUMBER_WIN * GRID_RESOLUTION_PERWIN[0]  # 20
CELL_W = float(RESIZED_IMG_SIZE) / GRID_FINE_W  # 56.0
CELL_H = float(RESIZED_IMG_SIZE) / GRID_FINE_H  # 56.0

ANN_FILE = osp.join(GIT_ROOT, 'data/infos/nuscenes_infos_temporal_train.pkl')
SAVE_DIR = osp.join(GIT_ROOT, 'ssd_workspace/VIS/threshold_explore_v2/')

# Thresholds: IoB = intersection / bbox_area
THRESHOLDS = [0.0, 0.01, 0.02, 0.05, 0.10, 0.20]

TARGET_TOKEN = 'f701b2682fcc4f2eaac473101a424f31'

CLASS_COLORS_BGR = {
    'car': (0, 200, 0), 'truck': (200, 100, 0), 'bus': (0, 100, 200),
    'trailer': (200, 0, 200), 'pedestrian': (0, 165, 255), 'barrier': (128, 128, 128),
    'traffic_cone': (0, 0, 255), 'motorcycle': (255, 0, 128),
    'construction_vehicle': (0, 200, 200), 'bicycle': (255, 128, 0),
}


def get_corners_lidar(box):
    x, y, z, l, w, h, yaw = box[:7]
    dx, dy, dz = l / 2.0, w / 2.0, h / 2.0
    corners = np.array([
        [dx, dy, dz], [dx, -dy, dz], [-dx, -dy, dz], [-dx, dy, dz],
        [dx, dy, -dz], [dx, -dy, -dz], [-dx, -dy, -dz], [-dx, dy, -dz]
    ])
    c, s = np.cos(yaw), np.sin(yaw)
    R = np.array([[c, -s, 0], [s, c, 0], [0, 0, 1]])
    corners = (R @ corners.T).T
    corners[:, 0] += x; corners[:, 1] += y; corners[:, 2] += z
    return corners


def compute_cells_with_iob(min_u, max_u, min_v, max_v, cur_w, cur_h):
    """
    Compute overlap-based cells with IoB = intersection(cell, bbox) / bbox_area.
    Returns: list of (cell_id, iob, intersection_area) tuples.
    """
    fine_cell_w = float(cur_w) / GRID_FINE_W
    fine_cell_h = float(cur_h) / GRID_FINE_H

    # Clamp bbox to image
    min_u_c = max(0.0, min_u)
    max_u_c = min(float(cur_w), max_u)
    min_v_c = max(0.0, min_v)
    max_v_c = min(float(cur_h), max_v)

    bbox_area = max((max_u_c - min_u_c) * (max_v_c - min_v_c), 1e-6)

    if min_u_c >= max_u_c or min_v_c >= max_v_c:
        cx = (min_u + max_u) / 2.0
        cy = (min_v + max_v) / 2.0
        cc = int(cx / fine_cell_w)
        cr = int(cy / fine_cell_h)
        if 0 <= cc < GRID_FINE_W and 0 <= cr < GRID_FINE_H:
            return [(cr * GRID_FINE_W + cc, 1.0, bbox_area)], bbox_area
        return [], bbox_area

    c_start = max(0, min(GRID_FINE_W - 1, int(np.floor(min_u_c / fine_cell_w))))
    c_end = max(0, min(GRID_FINE_W - 1, int(np.floor(max_u_c / fine_cell_w))))
    r_start = max(0, min(GRID_FINE_H - 1, int(np.floor(min_v_c / fine_cell_h))))
    r_end = max(0, min(GRID_FINE_H - 1, int(np.floor(max_v_c / fine_cell_h))))

    results = []
    for r in range(r_start, r_end + 1):
        for c in range(c_start, c_end + 1):
            cx1 = c * fine_cell_w
            cx2 = (c + 1) * fine_cell_w
            cy1 = r * fine_cell_h
            cy2 = (r + 1) * fine_cell_h

            ix1 = max(cx1, min_u_c)
            ix2 = min(cx2, max_u_c)
            iy1 = max(cy1, min_v_c)
            iy2 = min(cy2, max_v_c)

            inter_area = max(0, ix2 - ix1) * max(0, iy2 - iy1)
            iob = inter_area / bbox_area

            cell_id = r * GRID_FINE_W + c
            results.append((cell_id, iob, inter_area))

    return results, bbox_area


def draw_threshold_view(vis_img_base, all_objects_data, threshold, cur_w, cur_h):
    """Draw cells passing the IoB threshold."""
    vis_img = vis_img_base.copy()
    fine_cell_w = float(cur_w) / GRID_FINE_W
    fine_cell_h = float(cur_h) / GRID_FINE_H

    cell_counts = defaultdict(int)
    cell_max_iob = defaultdict(float)
    cells_per_object = []

    for obj in all_objects_data:
        cells_iob = obj['cells_iob']
        passing = [(cid, iob) for cid, iob, _ in cells_iob if iob >= threshold]
        cells_per_object.append(len(passing))
        for cid, iob in passing:
            cell_counts[cid] += 1
            cell_max_iob[cid] = max(cell_max_iob[cid], iob)

    total_fg_cells = len(cell_counts)

    overlay = vis_img.copy()
    for cell_id, count in cell_counts.items():
        r = cell_id // GRID_FINE_W
        c = cell_id % GRID_FINE_W
        x1 = int(c * fine_cell_w)
        y1 = int(r * fine_cell_h)
        x2 = int((c + 1) * fine_cell_w)
        y2 = int((r + 1) * fine_cell_h)

        iob = cell_max_iob[cell_id]

        if count >= 3:
            base_color = np.array([0, 0, 255], dtype=np.float32)
        elif count == 2:
            base_color = np.array([0, 165, 255], dtype=np.float32)
        else:
            base_color = np.array([0, 200, 0], dtype=np.float32)

        # Brightness = max(0.3, min(1.0, iob * 10)) to make low IoB cells dimmer
        brightness = max(0.3, min(1.0, iob * 10))
        color = (base_color * brightness).astype(np.uint8).tolist()
        cv2.rectangle(overlay, (x1, y1), (x2, y2), color, -1)

        # Show IoB percentage
        if fine_cell_w > 40:
            iob_pct = f"{iob*100:.1f}" if iob < 0.1 else f"{iob*100:.0f}"
            cv2.putText(overlay, iob_pct, (x1 + 2, y2 - 5),
                        cv2.FONT_HERSHEY_SIMPLEX, 0.28, (255, 255, 255), 1)

    cv2.addWeighted(overlay, 0.4, vis_img, 0.6, 0, vis_img)

    # Grid lines
    for i in range(1, GRID_FINE_W):
        x = int(i * fine_cell_w)
        cv2.line(vis_img, (x, 0), (x, cur_h), (80, 80, 80), 1)
    for j in range(1, GRID_FINE_H):
        y = int(j * fine_cell_h)
        cv2.line(vis_img, (0, y), (cur_w, y), (80, 80, 80), 1)

    n_objects = len(all_objects_data)
    n_visible = sum(1 for o in all_objects_data if len(o['cells_iob']) > 0)
    zero_cell_visible = sum(1 for i, o in enumerate(all_objects_data)
                            if len(o['cells_iob']) > 0 and cells_per_object[i] == 0)
    avg_cells = np.mean([c for i, c in enumerate(cells_per_object)
                         if len(all_objects_data[i]['cells_iob']) > 0]) if n_visible > 0 else 0

    cv2.putText(vis_img, f"IoB >= {threshold:.0%}" if threshold >= 0.01 else f"IoB >= {threshold*100:.1f}%",
                (10, 30), cv2.FONT_HERSHEY_SIMPLEX, 0.8, (0, 255, 255), 2)
    cv2.putText(vis_img, f"{total_fg_cells} fg cells | avg {avg_cells:.1f}/vis_obj | {zero_cell_visible} vis_obj lost",
                (10, 60), cv2.FONT_HERSHEY_SIMPLEX, 0.5, (255, 255, 255), 1)

    return vis_img, {
        'threshold': threshold,
        'total_fg_cells': total_fg_cells,
        'n_visible': n_visible,
        'avg_cells_per_vis_obj': avg_cells,
        'zero_cell_visible': zero_cell_visible,
        'cells_per_object': cells_per_object,
    }


def process_sample(sample_info, save_prefix):
    cam_info = sample_info['cams']['CAM_FRONT']
    img_path = cam_info['data_path'].replace('./data/nuscenes/', 'data/nuscenes/')
    if not osp.isabs(img_path):
        img_path = osp.join(GIT_ROOT, img_path)

    img = cv2.imread(img_path)
    if img is None:
        print(f"  Cannot read: {img_path}")
        return

    orig_h, orig_w = img.shape[:2]
    cur_h = cur_w = RESIZED_IMG_SIZE
    sx = float(cur_w) / max(orig_w, 1e-6)
    sy = float(cur_h) / max(orig_h, 1e-6)

    K = np.array(cam_info['cam_intrinsic'], dtype=np.float32)
    R_sl = np.array(cam_info['sensor2lidar_rotation'], dtype=np.float32)
    t_sl = np.array(cam_info['sensor2lidar_translation'], dtype=np.float32)
    R_ls = R_sl.T
    t_ls = -R_ls @ t_sl.reshape(3,)

    gt_boxes = sample_info.get('gt_boxes', None)
    gt_names = sample_info.get('gt_names', None)
    if gt_boxes is None or gt_names is None:
        return

    gt_bboxes_3d = np.array(gt_boxes, dtype=np.float32)
    gt_names = np.array(gt_names)
    target_set = set(CLASSES)
    keep = np.array([n in target_set for n in gt_names])
    gt_bboxes_3d = gt_bboxes_3d[keep]
    gt_names_kept = gt_names[keep]
    if len(gt_names_kept) == 0:
        return

    vis_base = cv2.resize(img, (cur_w, cur_h))

    # Compute all objects' cells with IoB
    all_objects_data = []
    for g in range(len(gt_bboxes_3d)):
        box = gt_bboxes_3d[g].copy()
        cls_name = gt_names_kept[g]

        corners_lidar = get_corners_lidar(box[:7])
        corners_cam = (corners_lidar @ R_ls.T) + t_ls.reshape(1, 3)
        valid_z = corners_cam[:, 2] > 0
        if valid_z.sum() == 0:
            all_objects_data.append({'cls': cls_name, 'cells_iob': [], 'bbox_area': 0,
                                     'aabb': None})
            continue

        safe_Z = np.where(corners_cam[:, 2] < 1e-3, 1e-3, corners_cam[:, 2])
        u_all = (K[0, 0] * corners_cam[:, 0] + K[0, 2] * corners_cam[:, 2]) / safe_Z
        v_all = (K[1, 1] * corners_cam[:, 1] + K[1, 2] * corners_cam[:, 2]) / safe_Z
        u_img = u_all * sx
        v_img = v_all * sy

        min_u = float(np.min(u_img[valid_z]))
        max_u = float(np.max(u_img[valid_z]))
        min_v = float(np.min(v_img[valid_z]))
        max_v = float(np.max(v_img[valid_z]))

        cells_iob, bbox_area = compute_cells_with_iob(min_u, max_u, min_v, max_v, cur_w, cur_h)
        all_objects_data.append({
            'cls': cls_name,
            'cells_iob': cells_iob,
            'bbox_area': bbox_area,
            'aabb': (min_u, min_v, max_u, max_v),
        })

    # Draw AABBs on base
    vis_with_aabb = vis_base.copy()
    for obj in all_objects_data:
        if obj['aabb'] is None:
            continue
        min_u, min_v, max_u, max_v = obj['aabb']
        color = CLASS_COLORS_BGR.get(obj['cls'], (255, 255, 255))
        x1, y1 = int(max(0, min_u)), int(max(0, min_v))
        x2, y2 = int(min(cur_w - 1, max_u)), int(min(cur_h - 1, max_v))
        cv2.rectangle(vis_with_aabb, (x1, y1), (x2, y2), color, 2)
        # Label with bbox size
        bw, bh = int(max_u - min_u), int(max_v - min_v)
        ba = obj['bbox_area']
        n_cells = len(obj['cells_iob'])
        cv2.putText(vis_with_aabb, f"{obj['cls'][:3]}({bw}x{bh}) {n_cells}c",
                    (x1, max(15, y1 - 5)),
                    cv2.FONT_HERSHEY_SIMPLEX, 0.4, color, 1, cv2.LINE_AA)

    # Generate views for each threshold
    all_stats = []
    threshold_images = []

    for thr in THRESHOLDS:
        vis, stats = draw_threshold_view(vis_with_aabb, all_objects_data, thr, cur_w, cur_h)
        all_stats.append(stats)
        scaled = cv2.resize(vis, (560, 560))
        threshold_images.append(scaled)

    # Compose: 3 on top, 3 on bottom
    row1 = np.hstack(threshold_images[:3])
    row2 = np.hstack(threshold_images[3:])
    combined = np.vstack([row1, row2])

    os.makedirs(SAVE_DIR, exist_ok=True)
    save_path = osp.join(SAVE_DIR, f'{save_prefix}_iob_compare.jpg')
    cv2.imwrite(save_path, combined, [cv2.IMWRITE_JPEG_QUALITY, 95])
    print(f"\nSaved: {save_path}")

    # Individual high-res
    for i, thr in enumerate(THRESHOLDS):
        vis, _ = draw_threshold_view(vis_with_aabb, all_objects_data, thr, cur_w, cur_h)
        thr_str = f"{thr*100:.0f}" if thr >= 0.01 else f"{thr*100:.1f}"
        indiv_path = osp.join(SAVE_DIR, f'{save_prefix}_IoB_{thr_str}.jpg')
        cv2.imwrite(indiv_path, vis, [cv2.IMWRITE_JPEG_QUALITY, 95])

    # Per-object detail
    print(f"\n{'='*80}")
    print(f"Per-Object IoB Detail — {save_prefix}")
    print(f"{'='*80}")
    for i, obj in enumerate(all_objects_data):
        if obj['aabb'] is None:
            continue
        cls = obj['cls']
        ba = obj['bbox_area']
        cells = obj['cells_iob']
        iobs = [iob for _, iob, _ in cells]
        if not iobs:
            continue
        iobs_sorted = sorted(iobs, reverse=True)
        iob_str = ', '.join(f"{v*100:.1f}%" for v in iobs_sorted[:10])
        if len(iobs_sorted) > 10:
            iob_str += '...'
        min_u, min_v, max_u, max_v = obj['aabb']
        bw, bh = max_u - min_u, max_v - min_v
        print(f"  [{i:2d}] {cls:20s} bbox={bw:.0f}x{bh:.0f} ({ba:.0f}px²) "
              f"cells={len(cells):2d}  IoB: [{iob_str}]")

    # Stats table
    print(f"\n{'='*80}")
    print(f"IoB Threshold Summary")
    print(f"{'='*80}")
    print(f"{'Threshold':>10} {'FG Cells':>10} {'Avg/VisObj':>12} {'VisObj Lost':>12}")
    print(f"{'-'*50}")
    for s in all_stats:
        thr_str = f"{s['threshold']:.0%}" if s['threshold'] >= 0.01 else f"{s['threshold']*100:.1f}%"
        print(f"{thr_str:>10} {s['total_fg_cells']:>10} "
              f"{s['avg_cells_per_vis_obj']:>12.1f} {s['zero_cell_visible']:>12}")

    # IoB distribution
    print(f"\n{'='*80}")
    print("IoB Distribution (all cells across all visible objects)")
    print(f"{'='*80}")
    all_iobs = []
    for obj in all_objects_data:
        for cid, iob, _ in obj['cells_iob']:
            all_iobs.append(iob)
    if all_iobs:
        all_iobs_arr = np.array(all_iobs)
        bins = [0, 0.005, 0.01, 0.02, 0.05, 0.10, 0.20, 0.50, 1.01]
        for i in range(len(bins) - 1):
            lo, hi = bins[i], bins[i + 1]
            count = np.sum((all_iobs_arr >= lo) & (all_iobs_arr < hi))
            pct = 100 * count / len(all_iobs_arr)
            bar = '#' * int(pct / 2)
            lo_s = f"{lo*100:.1f}%" if lo < 0.01 else f"{lo*100:.0f}%"
            hi_s = f"{hi*100:.1f}%" if hi < 0.01 else f"{hi*100:.0f}%"
            print(f"  [{lo_s:>5}-{hi_s:>5}): {count:>4} cells ({pct:>5.1f}%) {bar}")


def aggregate_stats(infos, n_samples=200):
    """Aggregate IoB statistics over many samples."""
    import random
    random.seed(123)
    indices = list(range(len(infos)))
    random.shuffle(indices)

    agg = {thr: {'total_fg': 0, 'vis_objs': 0, 'lost_vis': 0, 'cells_list': []}
           for thr in THRESHOLDS}
    all_iobs_global = []

    count = 0
    for idx in indices:
        if count >= n_samples:
            break
        info = infos[idx]
        cam_info = info['cams']['CAM_FRONT']
        img_path = cam_info['data_path'].replace('./data/nuscenes/', 'data/nuscenes/')
        if not osp.isabs(img_path):
            img_path = osp.join(GIT_ROOT, img_path)
        if not osp.exists(img_path):
            continue

        orig_img = cv2.imread(img_path)
        if orig_img is None:
            continue
        orig_h, orig_w = orig_img.shape[:2]
        cur_h = cur_w = RESIZED_IMG_SIZE
        sx = float(cur_w) / max(orig_w, 1e-6)
        sy = float(cur_h) / max(orig_h, 1e-6)

        K = np.array(cam_info['cam_intrinsic'], dtype=np.float32)
        R_sl = np.array(cam_info['sensor2lidar_rotation'], dtype=np.float32)
        t_sl = np.array(cam_info['sensor2lidar_translation'], dtype=np.float32)
        R_ls = R_sl.T
        t_ls = -R_ls @ t_sl.reshape(3,)

        gt_boxes = info.get('gt_boxes', None)
        gt_names_arr = info.get('gt_names', None)
        if gt_boxes is None or gt_names_arr is None:
            continue
        gt_bboxes_3d = np.array(gt_boxes, dtype=np.float32)
        gt_names_arr = np.array(gt_names_arr)
        target_set = set(CLASSES)
        keep = np.array([n in target_set for n in gt_names_arr])
        gt_bboxes_3d = gt_bboxes_3d[keep]
        gt_names_kept = gt_names_arr[keep]
        if len(gt_names_kept) == 0:
            continue

        objects = []
        for g in range(len(gt_bboxes_3d)):
            box = gt_bboxes_3d[g].copy()
            corners_lidar = get_corners_lidar(box[:7])
            corners_cam = (corners_lidar @ R_ls.T) + t_ls.reshape(1, 3)
            valid_z = corners_cam[:, 2] > 0
            if valid_z.sum() == 0:
                objects.append([])
                continue
            safe_Z = np.where(corners_cam[:, 2] < 1e-3, 1e-3, corners_cam[:, 2])
            u_all = (K[0, 0] * corners_cam[:, 0] + K[0, 2] * corners_cam[:, 2]) / safe_Z
            v_all = (K[1, 1] * corners_cam[:, 1] + K[1, 2] * corners_cam[:, 2]) / safe_Z
            u_img = u_all * sx
            v_img = v_all * sy
            min_u = float(np.min(u_img[valid_z]))
            max_u = float(np.max(u_img[valid_z]))
            min_v = float(np.min(v_img[valid_z]))
            max_v = float(np.max(v_img[valid_z]))
            cells_iob, _ = compute_cells_with_iob(min_u, max_u, min_v, max_v, cur_w, cur_h)
            objects.append(cells_iob)
            for _, iob, _ in cells_iob:
                all_iobs_global.append(iob)

        for thr in THRESHOLDS:
            for obj_cells in objects:
                is_visible = len(obj_cells) > 0
                if not is_visible:
                    continue
                agg[thr]['vis_objs'] += 1
                passing = [cid for cid, iob, _ in obj_cells if iob >= thr]
                if not passing:
                    agg[thr]['lost_vis'] += 1
                agg[thr]['cells_list'].append(len(passing))
            fg_set = set()
            for obj_cells in objects:
                for cid, iob, _ in obj_cells:
                    if iob >= thr:
                        fg_set.add(cid)
            agg[thr]['total_fg'] += len(fg_set)

        count += 1

    print(f"\n{'='*80}")
    print(f"AGGREGATE IoB STATISTICS ({count} samples)")
    print(f"{'='*80}")
    print(f"{'Threshold':>10} {'Avg FG/frm':>12} {'Avg cell/obj':>14} {'VisObj Lost':>12} {'Lost %':>10}")
    print(f"{'-'*62}")
    for thr in THRESHOLDS:
        s = agg[thr]
        avg_fg = s['total_fg'] / max(count, 1)
        avg_cpo = np.mean(s['cells_list']) if s['cells_list'] else 0
        lost_pct = 100 * s['lost_vis'] / max(s['vis_objs'], 1)
        thr_str = f"{thr:.0%}" if thr >= 0.01 else f"{thr*100:.1f}%"
        print(f"{thr_str:>10} {avg_fg:>12.1f} {avg_cpo:>14.2f} "
              f"{s['lost_vis']:>12} {lost_pct:>9.1f}%")

    # Global IoB distribution
    if all_iobs_global:
        arr = np.array(all_iobs_global)
        print(f"\nGlobal IoB distribution ({len(arr)} total cell assignments):")
        bins = [0, 0.005, 0.01, 0.02, 0.05, 0.10, 0.20, 0.50, 1.01]
        for i in range(len(bins) - 1):
            lo, hi = bins[i], bins[i + 1]
            cnt = np.sum((arr >= lo) & (arr < hi))
            pct = 100 * cnt / len(arr)
            bar = '#' * int(pct / 2)
            lo_s = f"{lo*100:.1f}%" if lo < 0.01 else f"{lo*100:.0f}%"
            hi_s = f"{hi*100:.1f}%" if hi < 0.01 else f"{hi*100:.0f}%"
            print(f"  [{lo_s:>5}-{hi_s:>5}): {cnt:>6} ({pct:>5.1f}%) {bar}")


def main():
    print(f"Loading {ANN_FILE}...")
    with open(ANN_FILE, 'rb') as f:
        data = pickle.load(f)

    infos = data.get('infos', data.get('data_list', [])) if isinstance(data, dict) else data
    print(f"Total samples: {len(infos)}")

    # Find target sample
    target_info = None
    for info in infos:
        token = info.get('token', '')
        if token == TARGET_TOKEN:
            target_info = info
            break

    if target_info:
        print(f"\nProcessing target: {TARGET_TOKEN}")
        process_sample(target_info, TARGET_TOKEN)
    else:
        print(f"Target {TARGET_TOKEN} not found")

    # Aggregate
    aggregate_stats(infos, n_samples=200)


if __name__ == '__main__':
    main()
