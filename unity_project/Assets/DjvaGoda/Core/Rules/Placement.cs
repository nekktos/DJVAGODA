// Где можно ставить постройку (перенос build_controller.gd::is_spot_buildable).
//
// Два правила: земля под пятном не круче ступеньки в 7 м (пять лучей вниз —
// углы и середина — делает Unity-слой), и между пятном и чужими постройками
// зазор 3 м — иначе проход между домами закрывается и навигация рвётся.
using System;
using System.Collections.Generic;

namespace DjvaGoda.Core
{
    public static class Placement
    {
        public const float Clearance = 3f;
        public const float MaxStep = 7f;
        public const float PickDistance = 900f;

        /// Точки, куда Unity-слой бросает лучи вниз: четыре угла и середина.
        public static V3[] Probes(V3 point, BuildingKind kind)
        {
            var size = Res.BuildingSize(kind);
            float hx = size.X * 0.5f, hz = size.Z * 0.5f;
            return new[]
            {
                point + new V3(-hx, 0f, -hz), point + new V3(hx, 0f, -hz),
                point + new V3(-hx, 0f, hz), point + new V3(hx, 0f, hz), point,
            };
        }

        /// Высоты под лучами: null — луч ушёл в пустоту (край мира).
        public static bool GroundFits(float?[] heights)
        {
            float lowest = float.MaxValue, highest = float.MinValue;
            foreach (var h in heights)
            {
                if (!h.HasValue) return false;
                lowest = Math.Min(lowest, h.Value);
                highest = Math.Max(highest, h.Value);
            }
            return highest - lowest <= MaxStep;
        }

        /// Не налезает ли на уже стоящие (и строящиеся) постройки с зазором.
        public static bool Clear(V3 point, BuildingKind kind, IEnumerable<KeyValuePair<BuildingKind, V3>> buildings)
        {
            var size = Res.BuildingSize(kind);
            foreach (var other in buildings)
            {
                var otherSize = Res.BuildingSize(other.Key);
                float gapX = (size.X + otherSize.X) * 0.5f + Clearance;
                float gapZ = (size.Z + otherSize.Z) * 0.5f + Clearance;
                if (Math.Abs(other.Value.X - point.X) < gapX && Math.Abs(other.Value.Z - point.Z) < gapZ) return false;
            }
            return true;
        }

        /// Ставить ли в точке по рельефу ядра (без лучей) — для ИИ и проверок.
        public static bool Buildable(V3 point, BuildingKind kind, Relief relief,
            IEnumerable<KeyValuePair<BuildingKind, V3>> buildings)
        {
            var probes = Probes(point, kind);
            var heights = new float?[probes.Length];
            float half = MapLayout.WorldSize * 0.5f;
            for (int i = 0; i < probes.Length; i++)
            {
                var p = probes[i];
                if (Math.Abs(p.X) > half || Math.Abs(p.Z) > half) heights[i] = null;
                else heights[i] = relief.Height(p.X, p.Z);
            }
            return GroundFits(heights) && Clear(point, kind, buildings);
        }
    }
}
