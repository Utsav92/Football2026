"""Render a contact sheet of clip poses from player.blend (Workbench, headless).
  Blender -b <out>/player.blend --python Tools/blender/preview_poses.py -- out.png clip:frame [clip:frame ...]"""
import bpy, sys, math
from mathutils import Vector
argv = sys.argv[sys.argv.index('--') + 1:]
out, shots = argv[0], [a.split(':') for a in argv[1:]]
sc = bpy.context.scene
sc.render.engine = 'BLENDER_WORKBENCH'; sc.render.resolution_x = 360; sc.render.resolution_y = 520
sc.display.shading.light = 'STUDIO'; sc.display.shading.color_type = 'MATERIAL'
sc.world = bpy.data.worlds.new('w'); sc.world.color = (0.55, 0.62, 0.7)
arm = bpy.data.objects['skeleton']
cam = bpy.data.objects.new('cam', bpy.data.cameras.new('cam')); sc.collection.objects.link(cam); sc.camera = cam
cam.data.type = 'ORTHO'; cam.data.ortho_scale = 2.6
tiles = []
import os
for i, (clip, frame) in enumerate(shots):
    arm.animation_data.action = bpy.data.actions[clip]; sc.frame_set(int(frame))
    # side view from +X (character faces -Y: appears facing left)
    cam.location = (6, 0, 0.95); cam.rotation_euler = (math.radians(90), 0, math.radians(90))
    sc.render.filepath = f'{out}.{i}.png'; bpy.ops.render.render(write_still=True)
    tiles.append(sc.render.filepath)
import numpy as np
imgs = [bpy.data.images.load(t) for t in tiles]
w, h = imgs[0].size
sheet = np.concatenate([np.array(im.pixels[:]).reshape(h, w, 4) for im in imgs], axis=1)
o = bpy.data.images.new('sheet', w * len(imgs), h); o.pixels = sheet.flatten().tolist(); o.filepath_raw = out; o.file_format = 'PNG'; o.save()
print('SHEET', out)
