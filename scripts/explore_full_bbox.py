#!/usr/bin/env python
"""
Compare IoB using clamped vs full (unclamped) 2D bbox area.
Key question: objects mostly out-of-frame have huge unclamped bbox,
so their visible edge cells should get near-zero IoB.
"""

import sys, os, os.path as osp
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

ANN_FILE = osp.join(GIT_ROOT, 'data/infos/nuscenes_infos_temporal_train.pkl')
SAVE_DIR = osp.join(GIT_ROOT, 'ssd_workspace/VIS/threshold_explore_v3/')
TARGET_TOKEN = 'f701b2682fcc4f2eaac473101a424f31'

CLASS_COLORS_BGR = {
    'car': (0, 200, 0), 'truck': (200, 100, 0), 'bus': (0, 100, 200),
    'trailer': (200, 0, 200), 'pedestrian': (0, 165, 255), 'barrier': (128, 128, 128),
    'traffic_cone': (0, 0, 255), 'motorcycle': (255, 0, 128),
    'construction_vehicle': (0, 200, 200), 'bicycle': (255, 128, 0),
}

THRESHOLDS = [0.0, 0.005, 0.01, 0.02, 0.05, 0.10]


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


def compute_cells_full_iob(min_u, max_u, min_v, max_v, cur_w, cur_h):
    """
    IoB using FULL (unclamped) bbox area as denominator.
    Intersection is still clamped to image boundary.
    """
    fine_cell_w = float(cur_w) / GRID_FINE_W
    fine_cell_h = float(cur_h) / GRID_FINE_H

    # Full unclamped bbox area
    full_bbox_w = max_u - min_u
    full_bbox_h = max_v - min_v
    full_bbox_area = max(full_bbox_w * full_bbox_h, 1e-6)

    # Clamped bbox for actual cell computation
    min_u_c = max(0.0, min_u)
    max_u_c = min(float(cur_w), max_u)
    min_v_c = max(0.0, min_v)
    max_v_c = min(float(cur_h), max_v)

    clamped_bbox_area = max((max_u_c - min_u_c) * (max_v_c - min_v_c), 1e-6)
    visibility_ratio = clamped_bbox_area / full_bbox_area

    if min_u_c >= max_u_c or min_v_c >= max_v_c:
        cx = (min_u + max_u) / 2.0
        cy = (min_v + max_v) / 2.0
        cc = int(cx / fine_cell_w)
        cr = int(cy / fine_cell_h)
        if 0 <= cc < GRID_FINE_W and 0 <= cr < GRID_FINE_H:
            return [(cr * GRID_FINE_W + cc, 1.0)], full_bbox_area, clamped_bbox_area, visibility_ratio
        return [], full_bbox_area, clamped_bbox_area, visibility_ratio

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
            inter = max(0, ix2 - ix1) * max(0, iy2 - iy1)

            # IoB with FULL bbox area
            iob_full = inter / full_bbox_area
            results.append((r * GRID_FINE_W + c, iob_full))

    return results, full_bbox_area, clamped_bbox_area, visibility_ratio


def draw_view(vis_base, objects, threshold, cur_w, cur_h):
    vis = vis_base.copy()
    fw = float(cur_w) / GRID_FINE_W
    fh = float(cur_h) / GRID_FINE_H

    cell_counts = defaultdict(int)
    cell_max_iob = defaultdict(float)
    cells_per_obj = []

    for obj in objects:
        passing = [(cid, iob) for cid, iob in obj['cells'] if iob >= threshold]
        cells_per_obj.append(len(passing))
        for cid, iob in passing:
            cell_counts[cid] += 1
            cell_max_iob[cid] = max(cell_max_iob[cid], iob)

    overlay = vis.copy()
    for cid, cnt in cell_counts.items():
        r, c = cid // GRID_FINE_W, cid % GRID_FINE_W
        x1, y1 = int(c * fw), int(r * fh)
        x2, y2 = int((c+1) * fw), int((r+1) * fh)

        iob = cell_max_iob[cid]
        if cnt >= 3:
            base = (0, 0, 255)
        elif cnt == 2:
            base = (0, 165, 255)
        else:
            base = (0, 200, 0)

        bright = max(0.3, min(1.0, iob * 50))  # scale for visibility
        color = tuple(int(v * bright) for v in base)
        cv2.rectangle(overlay, (x1, y1), (x2, y2), color, -1)

        if fw > 40:
            txt = f"{iob*100:.2f}" if iob < 0.01 else f"{iob*100:.1f}"
            cv2.putText(overlay, txt, (x1+1, y2-4),
                        cv2.FONT_HERSHEY_SIMPLEX, 0.25, (255,255,255), 1)

    cv2.addWeighted(overlay, 0.4, vis, 0.6, 0, vis)

    for i in range(1, GRID_FINE_W):
        cv2.line(vis, (int(i*fw), 0), (int(i*fw), cur_h), (80,80,80), 1)
    for j in range(1, GRID_FINE_H):
        cv2.line(vis, (0, int(j*fh)), (cur_w, int(j*fh)), (80,80,80), 1)

    n_vis = sum(1 for o in objects if o['cells'])
    lost = sum(1 for i, o in enumerate(objects) if o['cells'] and cells_per_obj[i] == 0)
    avg_c = np.mean([c for i, c in enumerate(cells_per_obj) if objects[i]['cells']]) if n_vis else 0

    thr_s = f"{threshold*100:.1f}%" if threshold < 0.01 else f"{threshold*100:.0f}%"
    cv2.putText(vis, f"IoB(full) >= {thr_s}", (10, 30),
                cv2.FONT_HERSHEY_SIMPLEX, 0.8, (0, 255, 255), 2)
    cv2.putText(vis, f"{len(cell_counts)} fg | avg {avg_c:.1f}/obj | {lost} lost",
                (10, 58), cv2.FONT_HERSHEY_SIMPLEX, 0.5, (255,255,255), 1)

    return vis, {'thr': threshold, 'fg': len(cell_counts), 'avg': avg_c, 'lost': lost}


def process_sample(info, prefix):
    cam = info['cams']['CAM_FRONT']
    img_path = cam['data_path'].replace('./data/nuscenes/', 'data/nuscenes/')
    if not osp.isabs(img_path):
        img_path = osp.join(GIT_ROOT, img_path)
    img = cv2.imread(img_path)
    if img is None:
        return

    oh, ow = img.shape[:2]
    ch = cw = RESIZED_IMG_SIZE
    sx, sy = float(cw)/max(ow,1e-6), float(ch)/max(oh,1e-6)

    K = np.array(cam['cam_intrinsic'], dtype=np.float32)
    R_sl = np.array(cam['sensor2lidar_rotation'], dtype=np.float32)
    t_sl = np.array(cam['sensor2lidar_translation'], dtype=np.float32)
    R_ls = R_sl.T
    t_ls = -R_ls @ t_sl.reshape(3,)

    gt_boxes = np.array(info['gt_boxes'], dtype=np.float32)
    gt_names = np.array(info['gt_names'])
    keep = np.array([n in set(CLASSES) for n in gt_names])
    gt_boxes = gt_boxes[keep]
    gt_names = gt_names[keep]

    vis_base = cv2.resize(img, (cw, ch))
    objects = []

    print(f"\n{'='*100}")
    print(f"Per-Object: Clamped vs Full bbox — {prefix}")
    print(f"{'='*100}")
    print(f"{'':>4} {'Class':>20} {'Full bbox':>16} {'Clamped bbox':>16} "
          f"{'Full area':>12} {'Clamp area':>12} {'Visible%':>10} {'Cells':>6} "
          f"{'IoB(clamp)':>12} {'IoB(full)':>12}")
    print(f"{'-'*120}")

    for g in range(len(gt_boxes)):
        box = gt_boxes[g].copy()
        cls = gt_names[g]

        corners_lidar = get_corners_lidar(box[:7])
        corners_cam = (corners_lidar @ R_ls.T) + t_ls.reshape(1,3)
        valid_z = corners_cam[:, 2] > 0
        if valid_z.sum() == 0:
            objects.append({'cls': cls, 'cells': [], 'aabb': None})
            continue

        safe_Z = np.where(corners_cam[:,2] < 1e-3, 1e-3, corners_cam[:,2])
        u = (K[0,0]*corners_cam[:,0] + K[0,2]*corners_cam[:,2]) / safe_Z * sx
        v = (K[1,1]*corners_cam[:,1] + K[1,2]*corners_cam[:,2]) / safe_Z * sy

        min_u, max_u = float(np.min(u[valid_z])), float(np.max(u[valid_z]))
        min_v, max_v = float(np.min(v[valid_z])), float(np.max(v[valid_z]))

        cells, full_area, clamp_area, vis_ratio = compute_cells_full_iob(
            min_u, max_u, min_v, max_v, cw, ch)

        objects.append({
            'cls': cls, 'cells': cells,
            'aabb': (min_u, min_v, max_u, max_v),
            'full_area': full_area, 'clamp_area': clamp_area,
            'vis_ratio': vis_ratio,
        })

        if not cells:
            continue

        # Clamped dimensions
        cu1, cv1 = max(0, min_u), max(0, min_v)
        cu2, cv2_ = min(cw, max_u), min(ch, max_v)
        full_w, full_h = max_u - min_u, max_v - min_v
        clamp_w, clamp_h = cu2 - cu1, cv2_ - cv1

        iobs = [iob for _, iob in cells]
        iob_clamp_equiv = [iob * full_area / max(clamp_area, 1e-6) for iob in iobs]

        max_iob_full = max(iobs) if iobs else 0
        max_iob_clamp = max(iob_clamp_equiv) if iob_clamp_equiv else 0

        print(f"[{g:2d}] {cls:>20} {full_w:>6.0f}x{full_h:<6.0f} "
              f"{clamp_w:>6.0f}x{clamp_h:<6.0f} "
              f"{full_area:>12.0f} {clamp_area:>12.0f} {vis_ratio*100:>9.1f}% "
              f"{len(cells):>5} "
              f"{max_iob_clamp*100:>10.1f}% {max_iob_full*100:>10.2f}%")

    # Draw AABBs (clamped)
    vis_aabb = vis_base.copy()
    for obj in objects:
        if obj['aabb'] is None:
            continue
        mn_u, mn_v, mx_u, mx_v = obj['aabb']
        color = CLASS_COLORS_BGR.get(obj['cls'], (255,255,255))
        x1, y1 = int(max(0, mn_u)), int(max(0, mn_v))
        x2, y2 = int(min(cw-1, mx_u)), int(min(ch-1, mx_v))
        cv2.rectangle(vis_aabb, (x1, y1), (x2, y2), color, 2)

        vis_pct = obj.get('vis_ratio', 0) * 100
        fw_, fh_ = mx_u - mn_u, mx_v - mn_v
        label = f"{obj['cls'][:3]} full={int(fw_)}x{int(fh_)} vis={vis_pct:.0f}%"
        cv2.putText(vis_aabb, label, (x1, max(15, y1-5)),
                    cv2.FONT_HERSHEY_SIMPLEX, 0.35, color, 1, cv2.LINE_AA)

    # Generate threshold views
    os.makedirs(SAVE_DIR, exist_ok=True)
    images = []
    all_stats = []

    for thr in THRESHOLDS:
        v, s = draw_view(vis_aabb, objects, thr, cw, ch)
        all_stats.append(s)
        images.append(cv2.resize(v, (560, 560)))
        thr_s = f"{thr*100:.1f}" if thr < 0.01 else f"{thr*100:.0f}"
        cv2.imwrite(osp.join(SAVE_DIR, f'{prefix}_full_IoB_{thr_s}.jpg'), v,
                    [cv2.IMWRITE_JPEG_QUALITY, 95])

    row1 = np.hstack(images[:3])
    row2 = np.hstack(images[3:])
    combined = np.vstack([row1, row2])
    path = osp.join(SAVE_DIR, f'{prefix}_full_iob_compare.jpg')
    cv2.imwrite(path, combined, [cv2.IMWRITE_JPEG_QUALITY, 95])
    print(f"\nSaved: {path}")

    print(f"\n{'Threshold':>10} {'FG Cells':>10} {'Avg/obj':>10} {'Lost':>6}")
    print(f"{'-'*40}")
    for s in all_stats:
        ts = f"{s['thr']*100:.1f}%" if s['thr'] < 0.01 else f"{s['thr']*100:.0f}%"
        print(f"{ts:>10} {s['fg']:>10} {s['avg']:>10.1f} {s['lost']:>6}")


def aggregate(infos, n=200):
    import random
    random.seed(123)
    indices = list(range(len(infos)))
    random.shuffle(indices)

    agg = {t: {'fg': 0, 'vis': 0, 'lost': 0, 'cpo': []} for t in THRESHOLDS}
    all_iobs = []
    all_vis_ratios = []
    count = 0

    for idx in indices:
        if count >= n:
            break
        info = infos[idx]
        cam = info['cams']['CAM_FRONT']
        ip = cam['data_path'].replace('./data/nuscenes/', 'data/nuscenes/')
        if not osp.isabs(ip):
            ip = osp.join(GIT_ROOT, ip)
        if not osp.exists(ip):
            continue
        im = cv2.imread(ip)
        if im is None:
            continue
        oh, ow = im.shape[:2]
        ch = cw = RESIZED_IMG_SIZE
        sx, sy = float(cw)/max(ow,1e-6), float(ch)/max(oh,1e-6)

        K = np.array(cam['cam_intrinsic'], dtype=np.float32)
        R_sl = np.array(cam['sensor2lidar_rotation'], dtype=np.float32)
        t_sl = np.array(cam['sensor2lidar_translation'], dtype=np.float32)
        R_ls = R_sl.T
        t_ls = -R_ls @ t_sl.reshape(3,)

        gt_boxes = np.array(info.get('gt_boxes', []), dtype=np.float32)
        gt_names = np.array(info.get('gt_names', []))
        if len(gt_boxes) == 0:
            continue
        keep = np.array([n in set(CLASSES) for n in gt_names])
        gt_boxes, gt_names = gt_boxes[keep], gt_names[keep]
        if len(gt_names) == 0:
            continue

        objs = []
        for g in range(len(gt_boxes)):
            box = gt_boxes[g].copy()
            cl = get_corners_lidar(box[:7])
            cc = (cl @ R_ls.T) + t_ls.reshape(1,3)
            vz = cc[:,2] > 0
            if vz.sum() == 0:
                objs.append([])
                continue
            sz = np.where(cc[:,2]<1e-3, 1e-3, cc[:,2])
            uu = (K[0,0]*cc[:,0]+K[0,2]*cc[:,2])/sz * sx
            vv = (K[1,1]*cc[:,1]+K[1,2]*cc[:,2])/sz * sy
            mu, xu = float(np.min(uu[vz])), float(np.max(uu[vz]))
            mv, xv = float(np.min(vv[vz])), float(np.max(vv[vz]))
            cells, fa, ca, vr = compute_cells_full_iob(mu, xu, mv, xv, cw, ch)
            objs.append(cells)
            all_vis_ratios.append(vr)
            for _, iob in cells:
                all_iobs.append(iob)

        for t in THRESHOLDS:
            fgs = set()
            for oc in objs:
                if not oc:
                    continue
                agg[t]['vis'] += 1
                ps = [c for c, iob in oc if iob >= t]
                if not ps:
                    agg[t]['lost'] += 1
                agg[t]['cpo'].append(len(ps))
                fgs.update(ps)
            agg[t]['fg'] += len(fgs)
        count += 1

    print(f"\n{'='*80}")
    print(f"AGGREGATE with FULL bbox IoB ({count} samples)")
    print(f"{'='*80}")
    print(f"{'Threshold':>10} {'Avg FG/frm':>12} {'Avg cell/obj':>14} {'Lost':>8} {'Lost%':>8}")
    print(f"{'-'*55}")
    for t in THRESHOLDS:
        s = agg[t]
        af = s['fg']/max(count,1)
        ac = np.mean(s['cpo']) if s['cpo'] else 0
        lp = 100*s['lost']/max(s['vis'],1)
        ts = f"{t*100:.1f}%" if t < 0.01 else f"{t*100:.0f}%"
        print(f"{ts:>10} {af:>12.1f} {ac:>14.2f} {s['lost']:>8} {lp:>7.1f}%")

    if all_iobs:
        arr = np.array(all_iobs)
        print(f"\nGlobal IoB(full) distribution ({len(arr)} cells):")
        bins = [0, 0.001, 0.005, 0.01, 0.02, 0.05, 0.10, 0.20, 0.50, 1.01]
        for i in range(len(bins)-1):
            lo, hi = bins[i], bins[i+1]
            c = np.sum((arr>=lo)&(arr<hi))
            p = 100*c/len(arr)
            bar = '#'*int(p/2)
            print(f"  [{lo*100:>5.1f}%-{hi*100:>5.1f}%): {c:>6} ({p:>5.1f}%) {bar}")

    if all_vis_ratios:
        vr = np.array(all_vis_ratios)
        print(f"\nVisibility ratio distribution ({len(vr)} objects):")
        bins = [0, 0.1, 0.25, 0.5, 0.75, 1.01]
        for i in range(len(bins)-1):
            lo, hi = bins[i], bins[i+1]
            c = np.sum((vr>=lo)&(vr<hi))
            p = 100*c/len(vr)
            print(f"  [{lo*100:.0f}%-{hi*100:.0f}%): {c:>6} ({p:>5.1f}%)")


def main():
    print(f"Loading {ANN_FILE}...")
    with open(ANN_FILE, 'rb') as f:
        data = pickle.load(f)
    infos = data.get('infos', data.get('data_list', [])) if isinstance(data, dict) else data
    print(f"Total: {len(infos)}")

    target = None
    for info in infos:
        if info.get('token','') == TARGET_TOKEN:
            target = info
            break

    if target:
        process_sample(target, TARGET_TOKEN)

    aggregate(infos, n=200)


if __name__ == '__main__':
    main()
