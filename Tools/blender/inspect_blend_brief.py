import bpy
print("OBJS", [(o.name, o.type, len(o.data.vertices) if o.type=='MESH' else '') for o in bpy.data.objects])
print("ACTIONS", [(a.name, round(a.frame_range[1]-a.frame_range[0])) for a in bpy.data.actions])
print("ARM", [(o.name, len(o.data.bones)) for o in bpy.data.objects if o.type=='ARMATURE'])
print("FPS", bpy.context.scene.render.fps, "UNITS", bpy.context.scene.unit_settings.system, bpy.context.scene.unit_settings.scale_length)
print("MATS", [m.name for m in bpy.data.materials])
