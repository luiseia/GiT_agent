#!/usr/bin/env python
"""
Final visualization: vis>=10% + (IoF>=30% OR IoB>=20%)
IoB denominator uses FULL (unclamped) bbox area.
Generates baseline + filtered for 20 samples.
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
NUMBER_WIN = 5; GRID_RESOLUTION_PERWIN = (4, 4)
GRID_FINE_W = NUMBER_WIN * GRID_RESOLUTION_PERWIN[1]
GRID_FINE_H = NUMBER_WIN * GRID_RESOLUTION_PERWIN[0]
CELL_W = float(RESIZED_IMG_SIZE) / GRID_FINE_W
CELL_H = float(RESIZED_IMG_SIZE) / GRID_FINE_H
CELL_AREA = CELL_W * CELL_H

ANN_FILE = osp.join(GIT_ROOT, 'data/infos/nuscenes_infos_temporal_train.pkl')
SAVE_DIR = osp.join(GIT_ROOT, 'ssd_workspace/VIS/final_v10_IoF30_IoB20_fullbbox/')

CLASS_COLORS_BGR = {
    'car': (0,200,0), 'truck': (200,100,0), 'bus': (0,100,200),
    'trailer': (200,0,200), 'pedestrian': (0,165,255), 'barrier': (128,128,128),
    'traffic_cone': (0,0,255), 'motorcycle': (255,0,128),
    'construction_vehicle': (0,200,200), 'bicycle': (255,128,0),
}

# Final config
MIN_VIS = 0.10
MIN_IOF = 0.30
MIN_IOB = 0.20

TARGET_TOKENS = ['f701b2682fcc4f2eaac473101a424f31', '2736362f288949f9ad17f64eadc99119']
N_RANDOM = 18  # 2 target + 18 random = 20 total


def get_corners_lidar(box):
    x,y,z,l,w,h,yaw = box[:7]
    dx,dy,dz = l/2,w/2,h/2
    corners = np.array([[dx,dy,dz],[dx,-dy,dz],[-dx,-dy,dz],[-dx,dy,dz],
                         [dx,dy,-dz],[dx,-dy,-dz],[-dx,-dy,-dz],[-dx,dy,-dz]])
    c,s = np.cos(yaw),np.sin(yaw)
    R = np.array([[c,-s,0],[s,c,0],[0,0,1]])
    corners = (R@corners.T).T
    corners[:,0]+=x; corners[:,1]+=y; corners[:,2]+=z
    return corners


def compute_object_cells(min_u, max_u, min_v, max_v, cur_w, cur_h):
    fw = float(cur_w)/GRID_FINE_W; fh = float(cur_h)/GRID_FINE_H
    cell_area = fw*fh

    full_area = max((max_u-min_u)*(max_v-min_v), 1e-6)
    mu_c = max(0.0,min_u); xu_c = min(float(cur_w),max_u)
    mv_c = max(0.0,min_v); xv_c = min(float(cur_h),max_v)
    clamp_area = max((xu_c-mu_c)*(xv_c-mv_c), 1e-6)
    vis = clamp_area/full_area

    if mu_c >= xu_c or mv_c >= xv_c:
        cx,cy = (min_u+max_u)/2,(min_v+max_v)/2
        cc,cr = int(cx/fw),int(cy/fh)
        if 0<=cc<GRID_FINE_W and 0<=cr<GRID_FINE_H:
            return [{'id':cr*GRID_FINE_W+cc,'iof':1.0,'iob':1.0}], vis, full_area
        return [], vis, full_area

    cs = max(0,min(GRID_FINE_W-1,int(np.floor(mu_c/fw))))
    ce = max(0,min(GRID_FINE_W-1,int(np.floor(xu_c/fw))))
    rs = max(0,min(GRID_FINE_H-1,int(np.floor(mv_c/fh))))
    re = max(0,min(GRID_FINE_H-1,int(np.floor(xv_c/fh))))

    results = []
    for r in range(rs,re+1):
        for c in range(cs,ce+1):
            cx1,cx2 = c*fw,(c+1)*fw; cy1,cy2 = r*fh,(r+1)*fh
            ix1=max(cx1,mu_c); ix2=min(cx2,xu_c)
            iy1=max(cy1,mv_c); iy2=min(cy2,xv_c)
            inter = max(0,ix2-ix1)*max(0,iy2-iy1)
            iof = inter/cell_area
            iob = inter/full_area  # FULL bbox area as denominator
            results.append({'id':r*GRID_FINE_W+c, 'iof':iof, 'iob':iob})
    return results, vis, full_area


def project_objects(info):
    cam = info['cams']['CAM_FRONT']
    img_path = cam['data_path'].replace('./data/nuscenes/','data/nuscenes/')
    if not osp.isabs(img_path): img_path = osp.join(GIT_ROOT, img_path)
    img = cv2.imread(img_path)
    if img is None: return None, None
    oh,ow = img.shape[:2]; cw=ch=RESIZED_IMG_SIZE
    sx,sy = float(cw)/max(ow,1e-6), float(ch)/max(oh,1e-6)
    K = np.array(cam['cam_intrinsic'],dtype=np.float32)
    Rsl = np.array(cam['sensor2lidar_rotation'],dtype=np.float32)
    tsl = np.array(cam['sensor2lidar_translation'],dtype=np.float32)
    Rls=Rsl.T; tls=-Rls@tsl.reshape(3,)
    gt_boxes = np.array(info.get('gt_boxes',[]),dtype=np.float32)
    gt_names = np.array(info.get('gt_names',[]))
    if len(gt_boxes)==0: return None,None
    keep = np.array([n in set(CLASSES) for n in gt_names])
    gt_boxes,gt_names = gt_boxes[keep],gt_names[keep]
    if len(gt_names)==0: return None,None

    objects = []
    for g in range(len(gt_boxes)):
        box=gt_boxes[g].copy(); cls=gt_names[g]
        cl=get_corners_lidar(box[:7]); cc=(cl@Rls.T)+tls.reshape(1,3)
        vz=cc[:,2]>0
        if vz.sum()==0: continue
        sz=np.where(cc[:,2]<1e-3,1e-3,cc[:,2])
        uu=(K[0,0]*cc[:,0]+K[0,2]*cc[:,2])/sz*sx
        vv=(K[1,1]*cc[:,1]+K[1,2]*cc[:,2])/sz*sy
        mu=float(np.min(uu[vz])); xu=float(np.max(uu[vz]))
        mv=float(np.min(vv[vz])); xv=float(np.max(vv[vz]))
        cells, vis, bbox_area = compute_object_cells(mu,xu,mv,xv,cw,ch)
        if not cells: continue
        objects.append({
            'cls':cls, 'cells':cells, 'vis':vis,
            'aabb':(mu,mv,xu,xv),
            'full_size':(xu-mu,xv-mv),
            'bbox_area': bbox_area,
            'bbox_vs_cell': bbox_area/CELL_AREA,
            'n_total': len(cells),
        })
    return objects, cv2.resize(img,(cw,ch))


def apply_filter(objects, min_vis, min_iof, min_iob):
    cell_counts = defaultdict(int)
    cell_max_iof = defaultdict(float)
    n_total = len(objects)
    n_vis_rej = 0; n_kept = 0; n_iof_lost = 0
    cells_per_obj = []
    obj_details = []

    for obj in objects:
        if obj['vis'] < min_vis:
            n_vis_rej += 1; cells_per_obj.append(0)
            obj_details.append({'status':'vis_rej','kept':0,'iob_saved':0})
            continue
        passing = [c for c in obj['cells']
                   if c['iof'] >= min_iof or c['iob'] >= min_iob]
        iob_saves = sum(1 for c in obj['cells']
                        if c['iof'] < min_iof and c['iob'] >= min_iob)
        cells_per_obj.append(len(passing))
        if passing:
            n_kept += 1
            for c in passing:
                cell_counts[c['id']] += 1
                cell_max_iof[c['id']] = max(cell_max_iof[c['id']], c['iof'])
            obj_details.append({'status':'kept','kept':len(passing),'iob_saved':iob_saves})
        else:
            n_iof_lost += 1
            obj_details.append({'status':'iof_lost','kept':0,'iob_saved':0})

    return {
        'cell_counts': cell_counts, 'cell_max_iof': cell_max_iof,
        'n_obj': n_total, 'n_vis_rej': n_vis_rej,
        'n_kept': n_kept, 'n_iof_lost': n_iof_lost,
        'total_fg': len(cell_counts), 'cells_per_obj': cells_per_obj,
        'obj_details': obj_details,
    }


def draw_image(vis_base, objects, result, title, cfg_vis, cfg_iof, cfg_iob, cur_w, cur_h):
    vis = vis_base.copy()
    fw=float(cur_w)/GRID_FINE_W; fh=float(cur_h)/GRID_FINE_H

    for obj in objects:
        if obj['aabb'] is None: continue
        mu,mv,xu,xv = obj['aabb']
        color = CLASS_COLORS_BGR.get(obj['cls'],(255,255,255))
        rejected = obj['vis'] < cfg_vis
        lc = (0,0,180) if rejected else color
        th = 1 if rejected else 2
        x1,y1=int(max(0,mu)),int(max(0,mv))
        x2,y2=int(min(cur_w-1,xu)),int(min(cur_h-1,xv))
        cv2.rectangle(vis,(x1,y1),(x2,y2),lc,th)
        fw_,fh_=obj['full_size']
        bvc = obj['bbox_vs_cell']
        label = f"{obj['cls'][:3]} {int(fw_)}x{int(fh_)} bvc={bvc:.1f}"
        if rejected: label += " [REJ]"
        cv2.putText(vis,label,(x1,max(12,y1-4)),
                    cv2.FONT_HERSHEY_SIMPLEX,0.30,lc,1,cv2.LINE_AA)

    cc=result['cell_counts']; cm=result['cell_max_iof']
    overlay=vis.copy()
    for cid,cnt in cc.items():
        r,c=cid//GRID_FINE_W,cid%GRID_FINE_W
        x1,y1=int(c*fw),int(r*fh); x2,y2=int((c+1)*fw),int((r+1)*fh)
        iof=cm[cid]
        if cnt>=3: base=(0,0,255)
        elif cnt==2: base=(0,165,255)
        else: base=(0,200,0)
        bright=max(0.3,min(1.0,iof))
        color=tuple(int(v*bright) for v in base)
        cv2.rectangle(overlay,(x1,y1),(x2,y2),color,-1)
        if fw>40:
            cv2.putText(overlay,f"{int(iof*100)}",(x1+2,y2-5),
                        cv2.FONT_HERSHEY_SIMPLEX,0.28,(255,255,255),1)
    cv2.addWeighted(overlay,0.35,vis,0.65,0,vis)

    for i in range(1,GRID_FINE_W):
        cv2.line(vis,(int(i*fw),0),(int(i*fw),cur_h),(80,80,80),1)
    for j in range(1,GRID_FINE_H):
        cv2.line(vis,(0,int(j*fh)),(cur_w,int(j*fh)),(80,80,80),1)

    r=result
    cv2.putText(vis,title,(10,28),cv2.FONT_HERSHEY_SIMPLEX,0.50,(0,255,255),2)
    cv2.putText(vis,f"{r['total_fg']}fg | {r['n_kept']}/{r['n_obj']}obj | vRej={r['n_vis_rej']} iLost={r['n_iof_lost']}",
                (10,50),cv2.FONT_HERSHEY_SIMPLEX,0.38,(255,255,255),1)
    return vis


def process_sample(info, token, save_dir):
    objects, vis_img = project_objects(info)
    if objects is None: return None
    cw=ch=RESIZED_IMG_SIZE

    # Baseline (no filter)
    res_base = apply_filter(objects, 0.0, 0.0, 0.0)
    img_base = draw_image(vis_img, objects, res_base, 'baseline', 0.0, 0.0, 0.0, cw, ch)
    cv2.imwrite(osp.join(save_dir,f'{token}_baseline.jpg'), img_base, [cv2.IMWRITE_JPEG_QUALITY,95])

    # Filtered
    res_filt = apply_filter(objects, MIN_VIS, MIN_IOF, MIN_IOB)
    img_filt = draw_image(vis_img, objects, res_filt,
                          'v10+IoF30|IoB20(full)', MIN_VIS, MIN_IOF, MIN_IOB, cw, ch)
    cv2.imwrite(osp.join(save_dir,f'{token}_filtered.jpg'), img_filt, [cv2.IMWRITE_JPEG_QUALITY,95])

    # Print detail
    print(f"\n{'='*100}")
    print(f"Sample: {token}")
    print(f"{'='*100}")
    print(f"{'Class':>14} {'Bbox':>10} {'bv/c':>5} {'Vis%':>5} {'#C':>3} {'base':>6} {'filt':>6} {'IoB+':>5} {'status':>8}")
    print('-'*80)

    for i,obj in enumerate(objects):
        fw_,fh_=obj['full_size']; bvc=obj['bbox_vs_cell']
        cpo_b = res_base['cells_per_obj'][i]
        cpo_f = res_filt['cells_per_obj'][i]
        det = res_filt['obj_details'][i]
        iob_s = f"+{det['iob_saved']}" if det['iob_saved']>0 else ''
        print(f"{obj['cls']:>14} {int(fw_):>4}x{int(fh_):<4} {bvc:>5.1f} {obj['vis']*100:>4.0f}% {obj['n_total']:>3} {cpo_b:>6} {cpo_f:>6} {iob_s:>5} {det['status']:>8}")

    print(f"\n{'TOTAL FG':>14} {'':>22} {'':>3} {res_base['total_fg']:>6} {res_filt['total_fg']:>6}")
    reduction = (1 - res_filt['total_fg']/max(res_base['total_fg'],1))*100
    print(f"  Reduction: {reduction:.0f}%")
    return res_base, res_filt


def main():
    print(f"Loading {ANN_FILE}...")
    with open(ANN_FILE,'rb') as f: data=pickle.load(f)
    infos = data.get('infos',data.get('data_list',[])) if isinstance(data,dict) else data
    print(f"Total: {len(infos)}")
    os.makedirs(SAVE_DIR,exist_ok=True)

    token_map = {info.get('token',''):i for i,info in enumerate(infos)}
    samples = []
    for t in TARGET_TOKENS:
        if t in token_map: samples.append((t,infos[token_map[t]]))

    random.seed(42); indices=list(range(len(infos))); random.shuffle(indices)
    added=0
    for idx in indices:
        if added>=N_RANDOM: break
        info=infos[idx]; token=info.get('token',f's_{idx}')
        if token in [t for t,_ in samples]: continue
        if len(info.get('gt_names',[]))<3: continue
        cam=info['cams']['CAM_FRONT']
        ip=cam['data_path'].replace('./data/nuscenes/','data/nuscenes/')
        if not osp.isabs(ip): ip=osp.join(GIT_ROOT,ip)
        if not osp.exists(ip): continue
        samples.append((token,info)); added+=1

    # Aggregate
    agg_base_fg = 0; agg_filt_fg = 0
    agg_kept = 0; agg_total = 0; agg_vis_rej = 0; agg_iof_lost = 0
    n = 0

    for token,info in samples:
        print(f"\nProcessing: {token}")
        result = process_sample(info, token, SAVE_DIR)
        if result is None: continue
        rb, rf = result
        agg_base_fg += rb['total_fg']
        agg_filt_fg += rf['total_fg']
        agg_kept += rf['n_kept']; agg_total += rf['n_obj']
        agg_vis_rej += rf['n_vis_rej']; agg_iof_lost += rf['n_iof_lost']
        n += 1

    print(f"\n\n{'='*80}")
    print(f"AGGREGATE ({n} samples) — IoB uses FULL bbox area")
    print(f"{'='*80}")
    print(f"  Baseline avg FG:  {agg_base_fg/max(n,1):.1f}")
    print(f"  Filtered avg FG:  {agg_filt_fg/max(n,1):.1f}")
    print(f"  FG reduction:     {(1-agg_filt_fg/max(agg_base_fg,1))*100:.1f}%")
    print(f"  Object kept:      {agg_kept}/{agg_total} ({100*agg_kept/max(agg_total,1):.1f}%)")
    print(f"  Vis rejected:     {agg_vis_rej} ({100*agg_vis_rej/max(agg_total,1):.1f}%)")
    print(f"  IoF lost:         {agg_iof_lost} ({100*agg_iof_lost/max(agg_total-agg_vis_rej,1):.1f}%)")
    print(f"\nOutput: {SAVE_DIR}")


if __name__=='__main__':
    main()
