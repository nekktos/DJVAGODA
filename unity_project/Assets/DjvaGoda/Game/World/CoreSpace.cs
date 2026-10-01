// Граница ядра и Unity: векторы и повороты.
//
// Ядро живёт в осях Unity: левая тройка, «вперёд» — +Z, «вправо» — +X, yaw —
// поворот вокруг вертикали в радианах, растёт вправо (как угол Y в
// Quaternion.Euler). Здесь — только перевод типов V3 ↔ Vector3 и радианы ↔
// кватернион, без отражений.
//
// Раньше ядро жило в осях Godot-версии (правая тройка, «вперёд» — −Z), и на
// границе z отражался; каждому скрипту приходилось помнить, что габариты
// отражать нельзя. 01.10.2026 ядро перевели на оси Unity — мир при этом не
// сдвинулся: план, рельеф и лес отражены вместе с формулами.
using DjvaGoda.Core;
using UnityEngine;

namespace DjvaGoda.Game
{
    public static class CoreSpace
    {
        public static Vector3 ToUnity(this V3 v) { return new Vector3(v.X, v.Y, v.Z); }

        public static V3 ToCore(this Vector3 v) { return new V3(v.x, v.y, v.z); }

        /// Поворот по yaw ядра: transform.forward — «вперёд» ядра.
        public static Quaternion YawToRotation(float yaw)
        {
            return Quaternion.Euler(0f, yaw * Mathf.Rad2Deg, 0f);
        }

        /// Обратное: yaw ядра по направлению взгляда transform.
        public static float RotationToYaw(Transform t)
        {
            var f = t.forward;
            return Mathf.Atan2(f.x, f.z);
        }
    }
}
