// Граница ядра и Unity: векторы и повороты.
//
// Координаты переносятся ОДИН К ОДНОМУ: (x, y, z) ядра — (x, y, z) Unity.
// Формула поворота вокруг вертикали у Godot и Unity в координатах одна и та
// же, поэтому смещения строя, объезд и прицел из ядра верны без пересчёта.
// Отличие одно: «вперёд» в ядре — это −Z (так было в Godot), а transform.forward
// в Unity — +Z. Отсюда +180° в YawToRotation. Мир на экране — зеркало
// Godot-версии; ассеты всё равно делаются заново.
using DjvaGoda.Core;
using UnityEngine;

namespace DjvaGoda.Game
{
    public static class CoreSpace
    {
        public static Vector3 ToUnity(this V3 v) { return new Vector3(v.X, v.Y, v.Z); }

        public static V3 ToCore(this Vector3 v) { return new V3(v.x, v.y, v.z); }

        /// Поворот, при котором transform.forward смотрит туда, куда ядро считает «вперёд».
        public static Quaternion YawToRotation(float coreYaw)
        {
            return Quaternion.Euler(0f, coreYaw * Mathf.Rad2Deg + 180f, 0f);
        }

        /// Обратное: yaw ядра по направлению взгляда transform.
        public static float RotationToYaw(Transform t)
        {
            var f = t.forward;
            return Mathf.Atan2(-f.x, -f.z);
        }

        /// Поворот смещения (строй, раскладка) — тот же, что Basis(UP, yaw) в ядре.
        public static Quaternion OffsetRotation(float coreYaw)
        {
            return Quaternion.Euler(0f, coreYaw * Mathf.Rad2Deg, 0f);
        }
    }
}
