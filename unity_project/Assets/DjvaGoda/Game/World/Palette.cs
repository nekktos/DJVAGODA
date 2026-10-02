// Материалы мира: ключ плана → текстура (своя, кодом: Editor/TextureBake),
// оттенок, плотность и гладкость на трипланарном шейдере DjvaGoda/Triplanar.
//
// Земля и рельеф — ОДНИМ материалом: разными низкий рельеф читался бы кляксами
// на поле (находка Godot-версии). Неподвижное — текстура в мировых
// координатах (у соседних кусков нет швов); движущееся (Moving) — в
// координатах объекта, иначе она «плывёт» по идущему.
//
// Нет текстур (не собраны) — прежняя заливка цветом на URP/Lit.
using System.Collections.Generic;
using DjvaGoda.Core;
using UnityEngine;

namespace DjvaGoda.Game
{
    public static class Palette
    {
        struct Spec
        {
            public string Texture;
            public Color Tint;
            /// Повторов текстуры на метр.
            public float Scale;
            public float Smoothness;

            public Spec(string texture, Color tint, float scale, float smoothness = 0.08f)
            {
                Texture = texture;
                Tint = tint;
                Scale = scale;
                Smoothness = smoothness;
            }
        }

        static readonly Color White = Color.white;

        static readonly Dictionary<string, Spec> Specs = new Dictionary<string, Spec>
        {
            { "ground", new Spec("grass", White, 0.25f) },
            { "road", new Spec("dirt", White, 0.25f) },
            // Пучки травы (GrassField): та же трава, чуть светлее земли — видно стебли.
            { "grass_blades", new Spec("grass", new Color(1.15f, 1.2f, 0.95f), 1.5f) },
            { "foliage", new Spec("foliage", White, 0.6f) },
            { "trunk", new Spec("bark", White, 1f) },
            { "bark", new Spec("bark", White, 1f) },
            { "needles", new Spec("needles", White, 0.8f) },
            { "stone", new Spec("stone_wall", White, 0.33f) },
            { "dark_stone", new Spec("dark_stone", White, 0.33f) },
            { "marble", new Spec("marble", White, 0.35f, 0.45f) },
            { "wood", new Spec("planks", White, 0.4f) },
            { "rock", new Spec("rock", White, 0.15f) },
            { "ore_1", new Spec("ore_stone", White, 0.5f) },
            { "ore_2", new Spec("ore_gold", White, 0.5f, 0.35f) },
            { "ore_3", new Spec("ore_iron", White, 0.5f) },
            { "ore_5", new Spec("ore_coal", White, 0.5f, 0.3f) },
            { "roof", new Spec("roof", White, 0.4f) },
            { "thatch", new Spec("thatch", White, 0.5f) },
            { "metal", new Spec("metal", White, 1.5f, 0.6f) },
            { "dark_metal", new Spec("metal", new Color(0.35f, 0.35f, 0.38f), 1.5f, 0.5f) },
            { "gold", new Spec("metal", new Color(1.0f, 0.78f, 0.30f), 1.5f, 0.7f) },
            { "leather", new Spec("leather", White, 2f) },
            { "accent", new Spec("cloth", new Color(0.72f, 0.24f, 0.22f), 3f) },
            { "linen", new Spec("cloth", new Color(0.82f, 0.76f, 0.62f), 3f) },
            { "skin", new Spec("skin", new Color(0.93f, 0.74f, 0.60f), 2f, 0.15f) },
            { "pale_skin", new Spec("skin", new Color(0.86f, 0.86f, 0.80f), 2f, 0.15f) },
            { "dark_skin", new Spec("skin", new Color(0.55f, 0.40f, 0.30f), 2f, 0.15f) },
            { "hair", new Spec("fur", new Color(0.30f, 0.20f, 0.12f), 4f) },
            { "fair_hair", new Spec("fur", new Color(0.85f, 0.75f, 0.45f), 4f) },
            { "horse", new Spec("fur", new Color(0.50f, 0.32f, 0.20f), 2f) },
            { "mane", new Spec("fur", new Color(0.12f, 0.09f, 0.07f), 3f) },
            { "wolf", new Spec("fur", new Color(0.55f, 0.55f, 0.55f), 2f) },
        };

        /// Заливки без текстуры: призрак постройки виден насквозь своим цветом.
        static readonly Dictionary<string, Color> Plain = new Dictionary<string, Color>
        {
            { "ghost_ok", new Color(0.35f, 0.85f, 0.35f) },
            { "ghost_bad", new Color(0.9f, 0.25f, 0.2f) },
        };

        /// Цвета прежних заглушек — запас, если текстуры ещё не собраны.
        static readonly Dictionary<string, Color> Fallback = new Dictionary<string, Color>
        {
            { "ground", new Color(0.36f, 0.47f, 0.26f) }, { "road", new Color(0.46f, 0.42f, 0.35f) },
            { "foliage", new Color(0.24f, 0.44f, 0.24f) }, { "trunk", new Color(0.33f, 0.25f, 0.17f) },
            { "bark", new Color(0.36f, 0.27f, 0.19f) }, { "needles", new Color(0.15f, 0.33f, 0.22f) },
            { "accent", new Color(0.72f, 0.24f, 0.22f) }, { "stone", new Color(0.58f, 0.57f, 0.54f) },
            { "dark_stone", new Color(0.27f, 0.26f, 0.28f) }, { "marble", new Color(0.86f, 0.84f, 0.80f) },
            { "wood", new Color(0.52f, 0.38f, 0.24f) }, { "rock", new Color(0.45f, 0.44f, 0.42f) },
            { "ore_1", new Color(0.62f, 0.61f, 0.58f) }, { "ore_2", new Color(0.85f, 0.68f, 0.20f) },
            { "ore_3", new Color(0.55f, 0.30f, 0.18f) }, { "ore_5", new Color(0.10f, 0.10f, 0.11f) },
        };

        /// Свечение: огонь, угли, заклинания (шейдер DjvaGoda/Glow).
        static readonly Dictionary<string, Color> GlowColors = new Dictionary<string, Color>
        {
            { "fire", new Color(1f, 0.45f, 0.12f) },
            { "embers", new Color(1f, 0.32f, 0.06f) },
            { "curse", new Color(0.62f, 0.22f, 0.95f) },
            { "heal", new Color(0.45f, 1f, 0.55f) },
            { "rally", new Color(1f, 0.85f, 0.35f) },
            { "nature", new Color(0.35f, 0.85f, 0.3f) },
        };

        static readonly Dictionary<string, Material> Cache = new Dictionary<string, Material>();
        static Material _stub, _triplanar, _glow;
        static bool _loaded;

        /// Материал неподвижного: текстура лежит в мире.
        public static Material Of(string key) { return Get(key, false); }

        /// Материал движущегося (люди, звери, повозки, снаряды): текстура едет с объектом.
        public static Material Moving(string key) { return Get(key, true); }

        /// Ткань цвета стороны — одежда, флаги; на людях и знамёнах — движущаяся.
        public static Material Side(Faction side) { return Moving("side_" + (int)side); }

        static void Load()
        {
            if (_loaded) return;
            _loaded = true;
            // Образцы из Resources держат шейдеры в сборке: шейдер без ссылки из
            // материала из сборки вырезается, и Shader.Find там вернёт null.
            _stub = Resources.Load<Material>("Stub");
            if (_stub == null) _stub = new Material(Shader.Find("Standard"));
            _triplanar = Resources.Load<Material>("Triplanar");
            _glow = Resources.Load<Material>("Glow");
        }

        /// Светящийся полупрозрачный материал (огонь, заклинания); нет образца — оттенок на заглушке.
        public static Material Glow(string key)
        {
            string id = "свечение " + key;
            Material material;
            if (Cache.TryGetValue(id, out material) && material != null) return material;
            Load();
            Color color;
            if (!GlowColors.TryGetValue(key, out color)) color = Color.white;
            if (_glow != null)
            {
                material = new Material(_glow) { name = "Мир " + id, enableInstancing = true };
                material.SetColor("_BaseColor", color);
            }
            else material = new Material(_stub) { name = "Заглушка " + id, color = color };
            Cache[id] = material;
            return material;
        }

        static Material Get(string key, bool moving)
        {
            string id = moving ? key + " (движется)" : key;
            Material material;
            if (Cache.TryGetValue(id, out material) && material != null) return material;
            Load();
            Spec spec;
            bool known = Specs.TryGetValue(key, out spec) || SideSpec(key, out spec);
            Texture2D texture = known && _triplanar != null && !Plain.ContainsKey(key)
                ? Resources.Load<Texture2D>("Textures/" + spec.Texture) : null;
            if (texture != null)
            {
                material = new Material(_triplanar) { name = "Мир " + id, enableInstancing = true };
                material.SetTexture("_BaseMap", texture);
                material.SetColor("_BaseColor", spec.Tint);
                material.SetFloat("_Scale", spec.Scale);
                material.SetFloat("_Smoothness", spec.Smoothness);
                material.SetFloat("_ObjectSpace", moving ? 1f : 0f);
            }
            else
            {
                Color color;
                if (!Plain.TryGetValue(key, out color) && !Fallback.TryGetValue(key, out color))
                    color = known ? spec.Tint : Color.magenta;
                material = new Material(_stub) { name = "Заглушка " + id, color = color, enableInstancing = true };
                if (material.HasProperty("_Smoothness")) material.SetFloat("_Smoothness", 0.1f);
                if (material.HasProperty("_Glossiness")) material.SetFloat("_Glossiness", 0.1f);
            }
            Cache[id] = material;
            return material;
        }

        /// «side_N» — ткань цвета стороны (Factions.Colors).
        static bool SideSpec(string key, out Spec spec)
        {
            spec = default(Spec);
            int side;
            if (!key.StartsWith("side_") || !int.TryParse(key.Substring(5), out side) || side < 0 || side >= Factions.Count)
                return false;
            var rgb = Factions.Colors[side];
            spec = new Spec("cloth", new Color(rgb.R, rgb.G, rgb.B), 3f);
            return true;
        }
    }
}
