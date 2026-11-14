# Pintor de paleta para Formica: Second Spring (B3).
# Panel en la barra lateral de la vista 3D (N → pestaña «Formica»): eliges fila y columna de
# assets/textures/palette.png y «Pintar» lleva las UV de las caras seleccionadas al centro de ese
# cuadrito. En modo objeto pinta todas las caras de los objetos seleccionados.
# Regla de la guía de arte: biselar primero y pintar después.
#
# Uso: abrir este archivo en el Editor de texto de Blender y pulsar «Ejecutar script» (Alt+P).
# Dónde tocar: si la paleta cambia de tamaño, PALETTE_SIZE y SWATCH; si cambian las familias, ROW_NAMES.

import bpy
import bmesh
from mathutils import Vector

PALETTE_SIZE = 64      # píxeles de lado de palette.png
SWATCH = 8             # píxeles de cada cuadrito
GRID = PALETTE_SIZE // SWATCH
MATERIAL_NAME = "palette"
IMAGE_NAME = "palette.png"
ROW_NAMES = [
    "Madera", "Piedra y arena", "Verdes", "Cobre | malaquita",
    "Arcilla y tierra", "Grises del Nexo", "Ámbar y fuego", "Agua | cristal",
]


def swatch_uv(row: int, col: int) -> Vector:
    # Centro del cuadrito. La fila 0 está arriba de la imagen, y en UV la v = 1 es arriba.
    return Vector(((col * SWATCH + SWATCH / 2) / PALETTE_SIZE,
                   1.0 - (row * SWATCH + SWATCH / 2) / PALETTE_SIZE))


def swatch_color(row: int, col: int):
    # Lee el color del píxel central de la imagen cargada (para la muestra del panel).
    img = bpy.data.images.get(IMAGE_NAME)
    if img is None or img.size[0] != PALETTE_SIZE:
        return (0.0, 0.0, 0.0)
    x = col * SWATCH + SWATCH // 2
    y = PALETTE_SIZE - 1 - (row * SWATCH + SWATCH // 2)   # pixels empieza abajo
    i = (y * PALETTE_SIZE + x) * 4
    return tuple(img.pixels[i:i + 3])


def _update_preview(self, _context) -> None:
    self.preview = swatch_color(self.row, self.col)


class FormicaPaletteSettings(bpy.types.PropertyGroup):
    row: bpy.props.IntProperty(name="Fila", min=0, max=GRID - 1, update=_update_preview)
    col: bpy.props.IntProperty(name="Columna", min=0, max=GRID - 1, update=_update_preview)
    preview: bpy.props.FloatVectorProperty(name="Color", subtype="COLOR_GAMMA", size=3, min=0.0, max=1.0)


class FORMICA_OT_paint_swatch(bpy.types.Operator):
    """Lleva las UV de las caras seleccionadas al cuadrito elegido de la paleta"""
    bl_idname = "formica.paint_swatch"
    bl_label = "Pintar"
    bl_options = {"REGISTER", "UNDO"}

    def execute(self, context):
        settings = context.scene.formica_palette
        target = swatch_uv(settings.row, settings.col)
        material = bpy.data.materials.get(MATERIAL_NAME)
        painted = 0
        objects = [o for o in context.selected_objects if o.type == "MESH"]
        if context.mode == "EDIT_MESH":
            objects = [o for o in context.objects_in_mode if o.type == "MESH"]
        for obj in objects:
            mesh = obj.data
            if material is not None and material.name not in mesh.materials:
                mesh.materials.append(material)
            if context.mode == "EDIT_MESH":
                bm = bmesh.from_edit_mesh(mesh)
            else:
                bm = bmesh.new()
                bm.from_mesh(mesh)
            uv = bm.loops.layers.uv.active or bm.loops.layers.uv.new("UVMap")
            for face in bm.faces:
                if context.mode == "EDIT_MESH" and not face.select:
                    continue
                for loop in face.loops:
                    loop[uv].uv = target
                painted += 1
            if context.mode == "EDIT_MESH":
                bmesh.update_edit_mesh(mesh)
            else:
                bm.to_mesh(mesh)
                bm.free()
        self.report({"INFO"}, "Caras pintadas: %d" % painted)
        return {"FINISHED"}


class FORMICA_PT_palette(bpy.types.Panel):
    bl_label = "Paleta"
    bl_space_type = "VIEW_3D"
    bl_region_type = "UI"
    bl_category = "Formica"

    def draw(self, context):
        settings = context.scene.formica_palette
        layout = self.layout
        layout.prop(settings, "row")
        layout.label(text=ROW_NAMES[settings.row])
        layout.prop(settings, "col")
        layout.prop(settings, "preview", text="")
        layout.operator("formica.paint_swatch", icon="BRUSH_DATA")


CLASSES = (FormicaPaletteSettings, FORMICA_OT_paint_swatch, FORMICA_PT_palette)


def register() -> None:
    for cls in CLASSES:
        bpy.utils.register_class(cls)
    bpy.types.Scene.formica_palette = bpy.props.PointerProperty(type=FormicaPaletteSettings)


def unregister() -> None:
    del bpy.types.Scene.formica_palette
    for cls in reversed(CLASSES):
        bpy.utils.unregister_class(cls)


if __name__ == "__main__":
    # Si ya estaba registrado (se ejecuta dos veces), se quita antes.
    try:
        unregister()
    except Exception:
        pass
    register()
