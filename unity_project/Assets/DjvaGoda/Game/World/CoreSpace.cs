// Граница ядра и Unity: векторы и повороты.
//
// Ядро живёт в осях Godot-версии: правая тройка, «вперёд» — −Z, yaw — поворот
// против часовой, если смотреть сверху. Unity — левая тройка, «вперёд» — +Z.
// Переход — ОТРАЖЕНИЕМ Z: (x, y, z) ядра = (x, y, −z) Unity, yaw меняет знак.
// Тогда мир в Unity выглядит как в Godot (зона злодея там же, где автор её
// помнит), «вперёд» ядра — это transform.forward, а «вправо» — transform.right,
// и управление не зеркалится.
//
// Первый заход переносил оси один к одному: формулы поворота совпадают, и
// ядро считалось верно, но мир на экране выходил зеркалом, а клавиша «вправо»
// уводила персонажа влево. Отражение Z — правильная смена тройки.
//
// Размеры (габариты коробок) — НЕ векторы положения: их z не отражается.
using DjvaGoda.Core;
using UnityEngine;

namespace DjvaGoda.Game
{
    public static class CoreSpace
    {
        /// Точка или направление ядра — в Unity.
        public static Vector3 ToUnity(this V3 v) { return new Vector3(v.X, v.Y, -v.Z); }

        /// Точка или направление Unity — в ядро.
        public static V3 ToCore(this Vector3 v) { return new V3(v.x, v.y, -v.z); }

        /// Габарит (ширина, высота, глубина) — без отражения.
        public static Vector3 SizeToUnity(this V3 v) { return new Vector3(v.X, v.Y, v.Z); }

        /// Поворот по yaw ядра: transform.forward смотрит туда, куда ядро считает «вперёд»,
        /// а смещения, повёрнутые в ядре на yaw, совпадают с повёрнутыми этим кватернионом.
        public static Quaternion YawToRotation(float coreYaw)
        {
            return Quaternion.Euler(0f, -coreYaw * Mathf.Rad2Deg, 0f);
        }

        /// Обратное: yaw ядра по направлению взгляда transform.
        public static float RotationToYaw(Transform t)
        {
            var f = t.forward.ToCore();
            return Mathf.Atan2(-f.X, -f.Z);
        }
    }
}
