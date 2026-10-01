// Серые заглушки: материал на каждый ключ плана мира.
//
// До ассетов автора мир — заливка цветом. Земля и рельеф — ОДНИМ материалом:
// разными низкий рельеф читался бы кляксами на поле (находка Godot-версии).
using System.Collections.Generic;
using DjvaGoda.Core;
using UnityEngine;

namespace DjvaGoda.Game
{
    public static class Palette
    {
        static readonly Dictionary<string, Color> Colors = new Dictionary<string, Color>
        {
            { "ground", new Color(0.36f, 0.47f, 0.26f) },
            { "road", new Color(0.46f, 0.42f, 0.35f) },
            { "foliage", new Color(0.24f, 0.44f, 0.24f) },
            { "trunk", new Color(0.33f, 0.25f, 0.17f) },
            // Процедурные деревья (TreeShapes): кора, хвоя елей; листва — foliage.
            { "bark", new Color(0.36f, 0.27f, 0.19f) },
            { "needles", new Color(0.15f, 0.33f, 0.22f) },
            { "accent", new Color(0.72f, 0.24f, 0.22f) },
            { "stone", new Color(0.58f, 0.57f, 0.54f) },
            { "dark_stone", new Color(0.27f, 0.26f, 0.28f) },
            { "marble", new Color(0.86f, 0.84f, 0.80f) },
            { "wood", new Color(0.52f, 0.38f, 0.24f) },
            { "rock", new Color(0.45f, 0.44f, 0.42f) },
            // Кучи руды у шахт: по номеру ResourceKind (камень 1, золото 2, железо 3, уголь 5).
            { "ore_1", new Color(0.62f, 0.61f, 0.58f) },
            { "ore_2", new Color(0.85f, 0.68f, 0.20f) },
            { "ore_3", new Color(0.55f, 0.30f, 0.18f) },
            { "ore_5", new Color(0.10f, 0.10f, 0.11f) },
        };

        static readonly Dictionary<string, Material> Cache = new Dictionary<string, Material>();
        static Material _template;

        public static Material Of(string key)
        {
            Material material;
            if (Cache.TryGetValue(key, out material) && material != null) return material;
            if (_template == null)
            {
                // Образец из Resources держит шейдер URP/Lit в сборке: шейдер, на
                // который не ссылается ни один материал, из сборки вырезается, и
                // Shader.Find там возвращает null (в редакторе — находит).
                _template = Resources.Load<Material>("Stub");
                if (_template == null) _template = new Material(Shader.Find("Standard"));
            }
            Color color;
            if (!Colors.TryGetValue(key, out color)) color = SideColor(key);
            material = new Material(_template) { name = "Заглушка " + key, color = color, enableInstancing = true };
            if (material.HasProperty("_Smoothness")) material.SetFloat("_Smoothness", 0.1f);
            if (material.HasProperty("_Glossiness")) material.SetFloat("_Glossiness", 0.1f);
            Cache[key] = material;
            return material;
        }

        /// Цвет стороны (Factions.Colors) — им красятся персонажи, пока нет ассетов.
        public static Material Side(Faction side) { return Of("side_" + (int)side); }

        static Color SideColor(string key)
        {
            int side;
            if (!key.StartsWith("side_") || !int.TryParse(key.Substring(5), out side) || side < 0 || side >= Factions.Count)
                return Color.magenta;
            var rgb = Factions.Colors[side];
            return new Color(rgb.R, rgb.G, rgb.B);
        }
    }
}
