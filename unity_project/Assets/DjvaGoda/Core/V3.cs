// Вектор ядра: ядро не знает UnityEngine.Vector3, Unity-слой переводит на границе.
using System;

namespace DjvaGoda.Core
{
    public struct V3
    {
        public readonly float X;
        public readonly float Y;
        public readonly float Z;

        public V3(float x, float y, float z)
        {
            X = x;
            Y = y;
            Z = z;
        }

        public static V3 operator +(V3 a, V3 b) { return new V3(a.X + b.X, a.Y + b.Y, a.Z + b.Z); }
        public static V3 operator -(V3 a, V3 b) { return new V3(a.X - b.X, a.Y - b.Y, a.Z - b.Z); }
        public static V3 operator *(V3 a, float k) { return new V3(a.X * k, a.Y * k, a.Z * k); }

        /// Расстояние по горизонтали: почти всё в игре меряется так.
        public float FlatDistance(V3 other)
        {
            float dx = X - other.X;
            float dz = Z - other.Z;
            return (float)Math.Sqrt(dx * dx + dz * dz);
        }

        public override string ToString()
        {
            return string.Format("({0:0.#}, {1:0.#}, {2:0.#})", X, Y, Z);
        }
    }
}
