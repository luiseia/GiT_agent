#!/usr/bin/env python
"""
Two-Stage Filtering Visualization:
  Stage 1 (object-level): visibility_ratio = clamped_bbox_area / full_bbox_area >= min_vis
  Stage 2 (cell-level):   IoF = intersection(cell, bbox) / cell_area >= min_iof

Visualize multiple samples with different parameter combos.
"""

import sys, os, os.path as osp
import numpy as np
import cv2
import pickle
from collections import defaultdict
import random

GIT_ROOT = '/home/UNT/yz0370/projects/GiT'
sys.path.insert(0, GIT_ROOT)

CLASSES = ["car", "truck", "bus", "trailer", "pedestrian", "barrier",
           "traffic_cone", "motorcycle", "construction_vehicle", "bicycle"]
RESIZED_IMG_SIZE = 1120
NUMBER_WIN = 5
GRID_RESOLUTION_PERWIN = (4, 4)
GRID_FINE_W = NUMBER_WIN * GRID_RESOLUTION_PERWIN[1]  # 20
GRID_FINE_H = NUMBER_WIN * GRID_RESOLUTION_PERWIN[0]  # 20
CELL_W = float(RESIZED_IMG_SIZE) / GRID_FINE_W  # 56
CELL_H = float(RESIZED_IMG_SIZE) / GRID_FINE_H  # 56
CELL_AREA = CELL_W * CELL_H  # 3136

ANN_FILE = osp.join(GIT_ROOT, 'data/infos/nuscenes_infos_temporal_train.pkl')
SAVE_DIR = osp.join(GIT_ROOT, 'ssd_workspace/VIS/two_stage/')

CLASS_COLORS_BGR = {
    'car': (0, 200, 0), 'truck': (200, 100, 0), 'bus': (0, 100, 200),
    'trailer': (200, 0, 200), 'pedestrian': (0, 165, 255), 'barrier': (128, 128, 128),
    'traffic_cone': (0, 0, 255), 'motorcycle': (255, 0, 128),
    'construction_vehicle': (0, 200, 200), 'bicycle': (255, 128, 0),
}

# Configs to compare
CONFIGS = [
    {'name': 'baseline (no filter)', 'min_vis': 0.0, 'min_iof': 0.0},
    {'name': 'vis>=25% only',        'min_vis': 0.25, 'min_iof': 0.0},
    {'name': 'vis>=25% + IoF>=10%',  'min_vis': 0.25, 'min_iof': 0.10},
    {'name': 'vis>=25% + IoF>=20%',  'min_vis': 0.25, 'min_iof': 0.20},
    {'name': 'vis>=25% + IoF>=30%',  'min_vis': 0.25, 'min_iof': 0.30},
    {'name': 'vis>=50% + IoF>=20%',  'min_vis': 0.50, 'min_iof': 0.20},
]

TARGET_TOKENS = [
    'f701b2682fcc4f2eaac473101a424f31',  # CEO referenced: ped + close truck
]
N_RANDOM = 9  # additional random samples


def get_corners_lidar(box):
    x, y, z, l, w, h, yaw = box[:7]
    dx, dy, dz = l/2, w/2, h/2
    corners = np.array([
        [dx,dy,dz],[dx,-dy,dz],[-dx,-dy,dz],[-dx,dy,dz],
        [dx,dy,-dz],[dx,-dy,-dz],[-dx,-dy,-dz],[-dx,dy,-dz]
    ])
    c, s = np.cos(yaw), np.sin(yaw)
    R = np.array([[c,-s,0],[s,c,0],[0,0,1]])
    corners = (R @ corners.T).T
    corners[:,0] += x; corners[:,1] += y; corners[:,2] += z
    return corners


def compute_object_cells(min_u, max_u, min_v, max_v, cur_w, cur_h):
    """Compute cells with both IoF and IoB metrics, plus visibility."""
    fw = float(cur_w) / GRID_FINE_W
    fh = float(cur_h) / GRID_FINE_H
    cell_area = fw * fh

    full_w = max_u - min_u
    full_h = max_v - min_v
    full_area = max(full_w * full_h, 1e-6)

    mu_c = max(0.0, min_u)
    xu_c = min(float(cur_w), max_u)
    mv_c = max(0.0, min_v)
    xv_c = min(float(cur_h), max_v)
    clamp_area = max((xu_c - mu_c) * (xv_c - mv_c), 1e-6)
    vis_ratio = clamp_area / full_area

    if mu_c >= xu_c or mv_c >= xv_c:
        cx, cy = (min_u+max_u)/2, (min_v+max_v)/2
        cc, cr = int(cx/fw), int(cy/fh)
        if 0 <= cc < GRID_FINE_W and 0 <= cr < GRID_FINE_H:
            return [{'id': cr*GRID_FINE_W+cc, 'iof': 1.0, 'iob': 1.0}], vis_ratio
        return [], vis_ratio

    cs = max(0, min(GRID_FINE_W-1, int(np.floor(mu_c/fw))))
    ce = max(0, min(GRID_FINE_W-1, int(np.floor(xu_c/fw))))
    rs = max(0, min(GRID_FINE_H-1, int(np.floor(mv_c/fh))))
    re = max(0, min(GRID_FINE_H-1, int(np.floor(xv_c/fh))))

    results = []
    for r in range(rs, re+1):
        for c in range(cs, ce+1):
            cx1, cx2 = c*fw, (c+1)*fw
            cy1, cy2 = r*fh, (r+1)*fh
            ix1 = max(cx1, mu_c); ix2 = min(cx2, xu_c)
            iy1 = max(cy1, mv_c); iy2 = min(cy2, xv_c)
            inter = max(0, ix2-ix1) * max(0, iy2-iy1)
            iof = inter / cell_area
            iob = inter / full_area
            results.append({'id': r*GRID_FINE_W+c, 'iof': iof, 'iob': iob})
    return results, vis_ratio


def project_objects(info):
    """Project all objects to CAM_FRONT, return object list with cells."""
    cam = info['cams']['CAM_FRONT']
    img_path = cam['data_path'].replace('./data/nuscenes/', 'data/nuscenes/')
    if not osp.isabs(img_path):
        img_path = osp.join(GIT_ROOT, img_path)

    img = cv2.imread(img_path)
    if img is None:
        return None, None

    oh, ow = img.shape[:2]
    cw = ch = RESIZED_IMG_SIZE
    sx, sy = float(cw)/max(ow,1e-6), float(ch)/max(oh,1e-6)

    K = np.array(cam['cam_intrinsic'], dtype=np.float32)
    Rsl = np.array(cam['sensor2lidar_rotation'], dtype=np.float32)
    tsl = np.array(cam['sensor2lidar_translation'], dtype=np.float32)
    Rls = Rsl.T; tls = -Rls @ tsl.reshape(3,)

    gt_boxes = np.array(info.get('gt_boxes',[]), dtype=np.float32)
    gt_names = np.array(info.get('gt_names',[]))
    if len(gt_boxes) == 0:
        return None, None
    keep = np.array([n in set(CLASSES) for n in gt_names])
    gt_boxes, gt_names = gt_boxes[keep], gt_names[keep]
    if len(gt_names) == 0:
        return None, None

    objects = []
    for g in range(len(gt_boxes)):
        box = gt_boxes[g].copy()
        cls = gt_names[g]
        cl = get_corners_lidar(box[:7])
        cc = (cl @ Rls.T) + tls.reshape(1,3)
        vz = cc[:,2] > 0
        if vz.sum() == 0:
            continue
        sz = np.where(cc[:,2]<1e-3, 1e-3, cc[:,2])
        uu = (K[0,0]*cc[:,0]+K[0,2]*cc[:,2])/sz * sx
        vv = (K[1,1]*cc[:,1]+K[1,2]*cc[:,2])/sz * sy
        mu = float(np.min(uu[vz])); xu = float(np.max(uu[vz]))
        mv = float(np.min(vv[vz])); xv = float(np.max(vv[vz]))

        cells, vis = compute_object_cells(mu, xu, mv, xv, cw, ch)
        if not cells:
            continue

        full_w, full_h = xu - mu, xv - mv
        objects.append({
            'cls': cls, 'cells': cells, 'vis': vis,
            'aabb': (mu, mv, xu, xv),
            'full_size': (full_w, full_h),
            'n_total_cells': len(cells),
        })

    vis_img = cv2.resize(img, (cw, ch))
    return objects, vis_img


def apply_filter(objects, min_vis, min_iof):
    """Apply two-stage filter, return cell_counts and stats."""
    cell_counts = defaultdict(int)
    cell_max_iof = defaultdict(float)
    n_obj_total = len(objects)
    n_obj_kept = 0
    n_obj_vis_rejected = 0
    cells_per_obj = []

    for obj in objects:
        # Stage 1: visibility
        if obj['vis'] < min_vis:
            n_obj_vis_rejected += 1
            cells_per_obj.append(0)
            continue

        # Stage 2: IoF per cell
        passing = [c for c in obj['cells'] if c['iof'] >= min_iof]
        cells_per_obj.append(len(passing))
        if passing:
            n_obj_kept += 1
        for c in passing:
            cell_counts[c['id']] += 1
            cell_max_iof[c['id']] = max(cell_max_iof[c['id']], c['iof'])

    n_obj_iof_lost = n_obj_total - n_obj_vis_rejected - n_obj_kept - \
                     sum(1 for i, o in enumerate(objects)
                         if o['vis'] >= min_vis and cells_per_obj[i] == 0
                         and len(o['cells']) > 0)
    # Recount properly
    n_passed_vis = sum(1 for o in objects if o['vis'] >= min_vis)
    n_lost_iof = sum(1 for i, o in enumerate(objects)
                     if o['vis'] >= min_vis and cells_per_obj[i] == 0)

    return {
        'cell_counts': cell_counts,
        'cell_max_iof': cell_max_iof,
        'n_obj': n_obj_total,
        'n_vis_rejected': n_obj_vis_rejected,
        'n_passed_vis': n_passed_vis,
        'n_lost_iof': n_lost_iof,
        'n_kept': n_obj_kept,
        'total_fg': len(cell_counts),
        'cells_per_obj': cells_per_obj,
    }


def draw_filtered(vis_base, objects, result, config_name, cur_w, cur_h):
    """Draw the filtered result."""
    vis = vis_base.copy()
    fw = float(cur_w) / GRID_FINE_W
    fh = float(cur_h) / GRID_FINE_H

    # Draw AABBs with visibility info
    for obj in objects:
        if obj['aabb'] is None:
            continue
        mu, mv, xu, xv = obj['aabb']
        color = CLASS_COLORS_BGR.get(obj['cls'], (255,255,255))
        x1, y1 = int(max(0,mu)), int(max(0,mv))
        x2, y2 = int(min(cur_w-1,xu)), int(min(cur_h-1,xv))

        vis_pct = obj['vis'] * 100
        rejected = obj['vis'] < result.get('_min_vis', 0)
        line_color = (0, 0, 180) if rejected else color
        thickness = 1 if rejected else 2
        cv2.rectangle(vis, (x1, y1), (x2, y2), line_color, thickness)

        fw_, fh_ = obj['full_size']
        label = f"{obj['cls'][:3]} {int(fw_)}x{int(fh_)} v={vis_pct:.0f}% {obj['n_total_cells']}c"
        if rejected:
            label += " [REJECTED]"
        cv2.putText(vis, label, (x1, max(12, y1-4)),
                    cv2.FONT_HERSHEY_SIMPLEX, 0.32, line_color, 1, cv2.LINE_AA)

    # Draw cells
    cc = result['cell_counts']
    cm = result['cell_max_iof']
    overlay = vis.copy()
    for cid, cnt in cc.items():
        r, c = cid // GRID_FINE_W, cid % GRID_FINE_W
        x1, y1 = int(c*fw), int(r*fh)
        x2, y2 = int((c+1)*fw), int((r+1)*fh)
        iof = cm[cid]

        if cnt >= 3: base = (0,0,255)
        elif cnt == 2: base = (0,165,255)
        else: base = (0,200,0)

        bright = max(0.3, min(1.0, iof))
        color = tuple(int(v*bright) for v in base)
        cv2.rectangle(overlay, (x1,y1), (x2,y2), color, -1)

        if fw > 40:
            txt = f"{int(iof*100)}"
            cv2.putText(overlay, txt, (x1+2, y2-5),
                        cv2.FONT_HERSHEY_SIMPLEX, 0.28, (255,255,255), 1)

    cv2.addWeighted(overlay, 0.35, vis, 0.65, 0, vis)

    # Grid
    for i in range(1, GRID_FINE_W):
        cv2.line(vis, (int(i*fw),0), (int(i*fw),cur_h), (80,80,80), 1)
    for j in range(1, GRID_FINE_H):
        cv2.line(vis, (0,int(j*fh)), (cur_w,int(j*fh)), (80,80,80), 1)

    # Stats
    r = result
    cv2.putText(vis, config_name, (10, 28),
                cv2.FONT_HERSHEY_SIMPLEX, 0.55, (0,255,255), 2)
    stats_txt = (f"{r['total_fg']} fg | {r['n_kept']}/{r['n_obj']} obj | "
                 f"vis_rej={r['n_vis_rejected']} iof_lost={r['n_lost_iof']}")
    cv2.putText(vis, stats_txt, (10, 52),
                cv2.FONT_HERSHEY_SIMPLEX, 0.4, (255,255,255), 1)

    return vis


def process_sample(info, token, save_dir):
    objects, vis_img = project_objects(info)
    if objects is None:
        return None

    cw = ch = RESIZED_IMG_SIZE
    config_images = []
    all_results = []

    for cfg in CONFIGS:
        result = apply_filter(objects, cfg['min_vis'], cfg['min_iof'])
        result['_min_vis'] = cfg['min_vis']
        all_results.append(result)

        vis = draw_filtered(vis_img, objects, result, cfg['name'], cw, ch)
        config_images.append(vis)

        # Save individual
        safe_name = cfg['name'].replace(' ', '_').replace('>=', 'ge').replace('%', 'pct')
        cv2.imwrite(osp.join(save_dir, f'{token}_{safe_name}.jpg'), vis,
                    [cv2.IMWRITE_JPEG_QUALITY, 95])

    # Compose 3x2 grid
    scaled = [cv2.resize(im, (560, 560)) for im in config_images]
    row1 = np.hstack(scaled[:3])
    row2 = np.hstack(scaled[3:])
    combined = np.vstack([row1, row2])
    cv2.imwrite(osp.join(save_dir, f'{token}_compare.jpg'), combined,
                [cv2.IMWRITE_JPEG_QUALITY, 95])

    # Print per-object detail
    print(f"\n{'='*90}")
    print(f"Sample: {token}")
    print(f"{'='*90}")
    print(f"{'Class':>16} {'FullBbox':>12} {'Vis%':>6} {'Cells':>6}  ", end='')
    for cfg in CONFIGS:
        print(f"  {cfg['name'][:12]:>12}", end='')
    print()
    print('-'*90)

    for i, obj in enumerate(objects):
        fw_, fh_ = obj['full_size']
        print(f"{obj['cls']:>16} {int(fw_):>5}x{int(fh_):<5} {obj['vis']*100:>5.1f} {obj['n_total_cells']:>5}  ", end='')
        for j, cfg in enumerate(CONFIGS):
            cpo = all_results[j]['cells_per_obj'][i]
            print(f"  {cpo:>12}", end='')
        print()

    print(f"\n{'TOTAL FG':>16} {'':>12} {'':>6} {'':>6}  ", end='')
    for r in all_results:
        print(f"  {r['total_fg']:>12}", end='')
    print()

    return all_results


def main():
    print(f"Loading {ANN_FILE}...")
    with open(ANN_FILE, 'rb') as f:
        data = pickle.load(f)
    infos = data.get('infos', data.get('data_list', [])) if isinstance(data, dict) else data
    print(f"Total: {len(infos)}")

    os.makedirs(SAVE_DIR, exist_ok=True)

    # Build token index
    token_map = {}
    for i, info in enumerate(infos):
        t = info.get('token', '')
        token_map[t] = i

    # Process target samples
    samples_to_process = []
    for t in TARGET_TOKENS:
        if t in token_map:
            samples_to_process.append((t, infos[token_map[t]]))

    # Add random diverse samples (prefer scenes with many objects)
    random.seed(42)
    indices = list(range(len(infos)))
    random.shuffle(indices)
    added = 0
    for idx in indices:
        if added >= N_RANDOM:
            break
        info = infos[idx]
        token = info.get('token', f'sample_{idx}')
        if token in [t for t, _ in samples_to_process]:
            continue
        gt_names = info.get('gt_names', [])
        if len(gt_names) < 3:  # want samples with multiple objects
            continue
        # Check image exists
        cam = info['cams']['CAM_FRONT']
        ip = cam['data_path'].replace('./data/nuscenes/', 'data/nuscenes/')
        if not osp.isabs(ip):
            ip = osp.join(GIT_ROOT, ip)
        if not osp.exists(ip):
            continue
        samples_to_process.append((token, info))
        added += 1

    # Process all
    agg = {i: {'fg': 0, 'kept': 0, 'total': 0, 'vis_rej': 0, 'iof_lost': 0, 'cpo': []}
           for i in range(len(CONFIGS))}

    for token, info in samples_to_process:
        print(f"\nProcessing: {token}")
        results = process_sample(info, token, SAVE_DIR)
        if results is None:
            continue
        for i, r in enumerate(results):
            agg[i]['fg'] += r['total_fg']
            agg[i]['kept'] += r['n_kept']
            agg[i]['total'] += r['n_obj']
            agg[i]['vis_rej'] += r['n_vis_rejected']
            agg[i]['iof_lost'] += r['n_lost_iof']
            agg[i]['cpo'].extend(r['cells_per_obj'])

    # Aggregate summary
    n = len(samples_to_process)
    print(f"\n\n{'='*90}")
    print(f"AGGREGATE SUMMARY ({n} samples)")
    print(f"{'='*90}")
    print(f"{'Config':>28} {'AvgFG':>8} {'Kept%':>8} {'VisRej%':>9} {'IoFLost%':>9} {'AvgC/obj':>10}")
    print('-'*75)
    for i, cfg in enumerate(CONFIGS):
        a = agg[i]
        avg_fg = a['fg'] / max(n, 1)
        kept_pct = 100 * a['kept'] / max(a['total'], 1)
        vis_rej_pct = 100 * a['vis_rej'] / max(a['total'], 1)
        iof_lost_pct = 100 * a['iof_lost'] / max(a['total'] - a['vis_rej'], 1)
        avg_cpo = np.mean([c for c in a['cpo'] if c > 0]) if any(c > 0 for c in a['cpo']) else 0
        print(f"{cfg['name']:>28} {avg_fg:>8.1f} {kept_pct:>7.1f}% {vis_rej_pct:>8.1f}% "
              f"{iof_lost_pct:>8.1f}% {avg_cpo:>10.1f}")

    print(f"\nImages saved to: {SAVE_DIR}")


if __name__ == '__main__':
    main()
