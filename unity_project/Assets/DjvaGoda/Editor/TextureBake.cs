// Текстуры игры — своими руками, кодом (решение автора от 02.10: «создай
// все модели и текстуры самостоятельно»). Ни одного чужого файла.
//
// Каждая текстура — функция от (u, v) в [0, 1): бесшовный шум с периодом
// (края сходятся), ячейки Вороного, кладка, доски, черепица, переплетение
// ткани. Результат — PNG в Resources/Textures (оттуда берёт Palette) и
// материал-образец Resources/Triplanar.mat: шейдер, на который ссылается
// материал, не вырезается из сборки.
//
// «ДжваГода → Собрать текстуры». Числа зерна постоянны: пересборка даёт те же
// файлы, и в истории нет лишних изменений.
using System;
using System.IO;
using UnityEditor;
using UnityEngine;

namespace DjvaGoda.EditorTools
{
    public static class TextureBake
    {
        public const string Folder = "Assets/DjvaGoda/Resources/Textures";
        public const int Size = 512;

        [MenuItem("ДжваГода/Собрать текстуры")]
        public static void BakeAll()
        {
            Directory.CreateDirectory(Folder);
            Save("grass", Grass);
            Save("dirt", Dirt);
            Save("rock", Rock);
            Save("bark", Bark);
            Save("foliage", Foliage);
            Save("needles", Needles);
            Save("planks", Planks);
            Save("stone_wall", (u, v) => Blocks(u, v, 0.62f, 11));
            Save("dark_stone", (u, v) => Blocks(u, v, 0.30f, 23));
            Save("marble", Marble);
            Save("roof", Roof);
            Save("thatch", Thatch);
            Save("metal", Metal);
            Save("cloth", Cloth);
            Save("leather", Leather);
            Save("skin", Skin);
            Save("fur", Fur);
            Save("ore_stone", (u, v) => Ore(u, v, new Color(0.62f, 0.61f, 0.58f), new Color(0.80f, 0.79f, 0.76f), 31));
            Save("ore_gold", (u, v) => Ore(u, v, new Color(0.40f, 0.38f, 0.34f), new Color(1.00f, 0.80f, 0.25f), 37));
            Save("ore_iron", (u, v) => Ore(u, v, new Color(0.42f, 0.33f, 0.28f), new Color(0.66f, 0.32f, 0.16f), 41));
            Save("ore_coal", (u, v) => Ore(u, v, new Color(0.12f, 0.12f, 0.13f), new Color(0.25f, 0.25f, 0.28f), 43));
            AssetDatabase.Refresh();
            foreach (var path in Directory.GetFiles(Folder, "*.png")) Configure(path.Replace('\\', '/'));
            EnsureTemplate();
            AssetDatabase.SaveAssets();
            Debug.Log("[текстуры] собрано в " + Folder);
        }

        /// Для сборки из командной строки: -executeMethod DjvaGoda.EditorTools.TextureBake.BakeMain
        public static void BakeMain() { BakeAll(); }

        static void Save(string name, Func<float, float, Color> pixel)
        {
            var texture = new Texture2D(Size, Size, TextureFormat.RGB24, false);
            var colors = new Color[Size * Size];
            for (int y = 0; y < Size; y++)
                for (int x = 0; x < Size; x++)
                    colors[y * Size + x] = pixel((float)x / Size, (float)y / Size);
            texture.SetPixels(colors);
            texture.Apply();
            File.WriteAllBytes(Folder + "/" + name + ".png", texture.EncodeToPNG());
            UnityEngine.Object.DestroyImmediate(texture);
        }

        static void Configure(string path)
        {
            var importer = AssetImporter.GetAtPath(path) as TextureImporter;
            if (importer == null) return;
            importer.wrapMode = TextureWrapMode.Repeat;
            importer.mipmapEnabled = true;
            importer.filterMode = FilterMode.Trilinear;
            importer.anisoLevel = 4;
            importer.sRGBTexture = true;
            importer.SaveAndReimport();
        }

        static void EnsureTemplate()
        {
            Template("Triplanar", "DjvaGoda/Triplanar");
            Template("Glow", "DjvaGoda/Glow");
        }

        static void Template(string name, string shaderName)
        {
            string path = "Assets/DjvaGoda/Resources/" + name + ".mat";
            if (AssetDatabase.LoadAssetAtPath<Material>(path) != null) return;
            var shader = Shader.Find(shaderName);
            if (shader == null)
            {
                Debug.LogError("[текстуры] шейдер " + shaderName + " не найден");
                return;
            }
            AssetDatabase.CreateAsset(new Material(shader) { name = name }, path);
        }

        // --- бесшовный шум ------------------------------------------------------

        static float Hash(int x, int y, int seed)
        {
            unchecked
            {
                uint h = (uint)(x * 374761393 + y * 668265263 + seed * 1274126177);
                h = (h ^ (h >> 13)) * 1274126177u;
                h ^= h >> 16;
                return (h & 0xFFFFFF) / (float)0x1000000;
            }
        }

        static int Wrap(int i, int period) { int m = i % period; return m < 0 ? m + period : m; }

        static float Smooth(float t) { return t * t * (3f - 2f * t); }

        /// Шум значений на решётке с периодом: u, v в [0, 1) — края сходятся.
        static float Value(float u, float v, int period, int seed) { return Value2(u, v, period, period, seed); }

        /// Шум с разными периодами по осям: волокна, хвоя, солома — вытянуты, но без шва.
        static float Value2(float u, float v, int px, int py, int seed)
        {
            int period = px;
            float x = u * px, y = v * py;
            int x0 = Mathf.FloorToInt(x), y0 = Mathf.FloorToInt(y);
            float fx = Smooth(x - x0), fy = Smooth(y - y0);
            float a = Hash(Wrap(x0, period), Wrap(y0, py), seed);
            float b = Hash(Wrap(x0 + 1, period), Wrap(y0, py), seed);
            float c = Hash(Wrap(x0, period), Wrap(y0 + 1, py), seed);
            float d = Hash(Wrap(x0 + 1, period), Wrap(y0 + 1, py), seed);
            return Mathf.Lerp(Mathf.Lerp(a, b, fx), Mathf.Lerp(c, d, fx), fy);
        }

        static float Fbm(float u, float v, int period, int octaves, int seed)
        {
            float sum = 0f, amp = 0.5f, norm = 0f;
            for (int i = 0; i < octaves; i++)
            {
                sum += Value(u, v, period << i, seed + i * 17) * amp;
                norm += amp;
                amp *= 0.5f;
            }
            return sum / norm;
        }

        /// Ячейки Вороного с периодом: расстояние до ближайшей и второй точки, номер ячейки.
        static void Voronoi(float u, float v, int period, int seed, out float f1, out float f2, out float id)
        {
            float x = u * period, y = v * period;
            int cx = Mathf.FloorToInt(x), cy = Mathf.FloorToInt(y);
            f1 = 9f;
            f2 = 9f;
            id = 0f;
            for (int dy = -1; dy <= 1; dy++)
                for (int dx = -1; dx <= 1; dx++)
                {
                    int gx = cx + dx, gy = cy + dy;
                    int wx = Wrap(gx, period), wy = Wrap(gy, period);
                    float px = gx + Hash(wx, wy, seed), py = gy + Hash(wx, wy, seed + 1);
                    float d = Mathf.Sqrt((px - x) * (px - x) + (py - y) * (py - y));
                    if (d < f1)
                    {
                        f2 = f1;
                        f1 = d;
                        id = Hash(wx, wy, seed + 2);
                    }
                    else if (d < f2) f2 = d;
                }
        }

        static Color Mix(Color a, Color b, float t) { return Color.Lerp(a, b, Mathf.Clamp01(t)); }

        static Color Shade(Color c, float k) { return new Color(c.r * k, c.g * k, c.b * k); }

        // --- природа -------------------------------------------------------------

        static Color Grass(float u, float v)
        {
            float patch = Fbm(u, v, 4, 4, 1);
            float blades = Value(u, v, 128, 2) * 0.6f + Value(u, v, 256, 3) * 0.4f;
            var dark = new Color(0.22f, 0.36f, 0.15f);
            var light = new Color(0.40f, 0.55f, 0.24f);
            var dry = new Color(0.55f, 0.55f, 0.28f);
            // Пятна мягкие: крупные перепады повторяются каждые 4 м и читаются сеткой.
            var c = Mix(dark, light, 0.35f + (patch - 0.5f) * 0.6f);
            c = Mix(c, dry, Mathf.Clamp01((Fbm(u, v, 3, 3, 9) - 0.66f) * 2f));
            c = Shade(c, 0.82f + blades * 0.36f);
            if (Hash((int)(u * 512), (int)(v * 512), 5) > 0.997f) c = new Color(0.85f, 0.80f, 0.35f);
            return c;
        }

        static Color Dirt(float u, float v)
        {
            float n = Fbm(u, v, 6, 5, 11);
            float f1, f2, id;
            Voronoi(u, v, 24, 12, out f1, out f2, out id);
            var c = Mix(new Color(0.36f, 0.29f, 0.21f), new Color(0.55f, 0.46f, 0.35f), n);
            // Галька: светлые камешки в части ячеек.
            if (id > 0.7f && f1 < 0.28f) c = Mix(c, new Color(0.62f, 0.60f, 0.55f), 1f - f1 / 0.28f);
            return Shade(c, 0.9f + Value(u, v, 192, 13) * 0.2f);
        }

        static Color Rock(float u, float v)
        {
            float n = Fbm(u, v, 5, 6, 21);
            float f1, f2, id;
            Voronoi(u, v, 4, 22, out f1, out f2, out id);
            // Трещины — тонкие линии по краям ячеек, а не мостовая из плиток.
            float crack = Mathf.Clamp01((f2 - f1) * 18f);
            var c = Mix(new Color(0.36f, 0.35f, 0.33f), new Color(0.62f, 0.61f, 0.58f), n * 0.9f + id * 0.12f);
            c = Shade(c, 0.7f + 0.3f * crack);
            // Пятна лишайника.
            float lichen = Mathf.Clamp01((Fbm(u, v, 4, 3, 24) - 0.68f) * 5f);
            return Mix(c, new Color(0.45f, 0.50f, 0.32f), lichen * 0.6f);
        }

        static Color Bark(float u, float v)
        {
            // Борозды вдоль ствола: шум сжат по горизонтали.
            float groove = Value2(u, v, 24, 3, 31) * 0.6f + Value2(u, v, 48, 6, 32) * 0.4f;
            float ridges = Mathf.Pow(Mathf.Abs(Mathf.Sin((u * 24f + Fbm(u, v, 4, 3, 33) * 3f) * Mathf.PI)), 0.6f);
            var c = Mix(new Color(0.20f, 0.14f, 0.09f), new Color(0.42f, 0.32f, 0.22f), groove * 0.7f + ridges * 0.4f);
            return Shade(c, 0.85f + Value(u, v, 128, 34) * 0.3f);
        }

        static Color Foliage(float u, float v)
        {
            float f1, f2, id;
            Voronoi(u, v, 32, 41, out f1, out f2, out id);
            float leaf = 1f - Mathf.Clamp01(f1 * 1.4f);
            var c = Mix(new Color(0.16f, 0.32f, 0.14f), new Color(0.36f, 0.56f, 0.24f), id * 0.7f + leaf * 0.5f);
            return Shade(c, 0.75f + Fbm(u, v, 4, 3, 42) * 0.4f);
        }

        static Color Needles(float u, float v)
        {
            // Хвоя: короткие штрихи вдоль ветви (без сдвига по диагонали — он даёт шов).
            float streak = Value2(u, v, 96, 6, 51) * 0.7f + Value2(u, v, 160, 10, 53) * 0.3f;
            var c = Mix(new Color(0.08f, 0.22f, 0.14f), new Color(0.22f, 0.40f, 0.26f), streak);
            return Shade(c, 0.8f + Fbm(u, v, 4, 3, 52) * 0.35f);
        }

        // --- постройки -----------------------------------------------------------

        /// Доски: четыре ряда на плитку, у каждой свой тон, волокна, щели, стыки вразбежку.
        static Color Planks(float u, float v)
        {
            const int rows = 4;
            float y = v * rows;
            int row = Mathf.FloorToInt(y);
            float fy = y - row;
            float shift = Hash(row, 0, 61);
            float x = u + shift;
            int plank = Mathf.FloorToInt(x * 2f);
            float fx = x * 2f - plank;
            float tone = Hash(row, Wrap(plank, 2), 62);
            float grain = Mathf.Sin((v * 90f + Fbm(u, v, 8, 3, 63) * 6f + tone * 10f) * Mathf.PI) * 0.5f + 0.5f;
            var c = Mix(new Color(0.38f, 0.26f, 0.15f), new Color(0.60f, 0.45f, 0.28f), tone * 0.6f + grain * 0.25f);
            c = Shade(c, 0.88f + Value(u, v, 64, 64) * 0.2f);
            float gap = Mathf.Min(fy, 1f - fy) * rows * 8f;
            float joint = Mathf.Min(fx, 1f - fx) * 60f;
            float edge = Mathf.Clamp01(Mathf.Min(gap, joint));
            return Shade(c, 0.35f + 0.65f * edge);
        }

        /// Кладка: тёсаные блоки вразбежку на растворе, у каждого свой тон.
        static Color Blocks(float u, float v, float brightness, int seed)
        {
            const int rows = 6;
            float y = v * rows;
            int row = Mathf.FloorToInt(y);
            float fy = y - row;
            float x = u * 3f + (row % 2) * 0.5f;
            int col = Mathf.FloorToInt(x);
            float fx = x - col;
            float tone = Hash(Wrap(col, 3), row, seed);
            float rough = Fbm(u, v, 8, 4, seed + 1);
            var stone = new Color(brightness, brightness * 0.98f, brightness * 0.94f);
            var c = Shade(stone, 0.75f + tone * 0.3f + (rough - 0.5f) * 0.35f);
            float mortar = Mathf.Min(Mathf.Min(fy, 1f - fy) * rows * 3.2f, Mathf.Min(fx, 1f - fx) * 9.6f);
            var mortarColor = Shade(stone, 1.15f);
            if (mortar < 0.25f) return Mix(Shade(mortarColor, 0.85f), c, mortar * 1.5f);
            // Скос у края блока — темнее, будто тень.
            return Shade(c, 0.85f + 0.15f * Mathf.Clamp01(mortar));
        }

        static Color Marble(float u, float v)
        {
            float n = Fbm(u, v, 4, 6, 71);
            float vein = Mathf.Abs(Mathf.Sin((u + v * 0.5f) * 6f * Mathf.PI + n * 12f));
            var c = Mix(new Color(0.78f, 0.76f, 0.72f), new Color(0.93f, 0.92f, 0.89f), n);
            // Прожилки — тонкие и неяркие: широкие тёмные волны читались камуфляжем.
            float line = Mathf.Clamp01(vein / 0.05f);
            return Mix(Shade(c, 0.72f), c, line * 0.85f + 0.15f);
        }

        /// Черепица: ряды полукруглых чешуек вразбежку, нижний край в тени.
        static Color Roof(float u, float v)
        {
            const int rows = 8;
            float y = v * rows;
            int row = Mathf.FloorToInt(y);
            float fy = y - row;
            float x = u * 8f + (row % 2) * 0.5f;
            int col = Mathf.FloorToInt(x);
            float fx = x - col - 0.5f;
            float arc = fy - (1f - Mathf.Sqrt(Mathf.Max(0f, 0.25f - fx * fx)) * 0.9f);
            float tone = Hash(Wrap(col, 8), row, 81);
            var c = Mix(new Color(0.45f, 0.17f, 0.12f), new Color(0.66f, 0.30f, 0.20f), tone * 0.7f + Fbm(u, v, 8, 3, 82) * 0.3f);
            float shade = Mathf.Clamp01(fy * 1.2f) * 0.5f + 0.5f;
            if (arc < 0f) shade *= 0.55f;
            return Shade(c, shade);
        }

        static Color Thatch(float u, float v)
        {
            float straw = Value2(u, v, 160, 8, 91) * 0.6f + Value2(u, v, 80, 8, 92) * 0.4f;
            float layer = Mathf.Repeat(v * 6f, 1f);
            var c = Mix(new Color(0.48f, 0.38f, 0.18f), new Color(0.80f, 0.68f, 0.38f), straw);
            return Shade(c, 0.7f + 0.3f * layer);
        }

        static Color Metal(float u, float v)
        {
            float brushed = Value2(u, v, 4, 256, 101) * 0.5f + Value2(u, v, 6, 128, 102) * 0.5f;
            float scratch = Hash((int)(u * 512) / 3, (int)(v * 512), 103) > 0.995f ? 0.2f : 0f;
            float g = 0.48f + brushed * 0.2f + scratch + (Fbm(u, v, 4, 3, 104) - 0.5f) * 0.1f;
            return new Color(g, g * 1.01f, g * 1.04f);
        }

        // --- люди и звери (светлые, красятся оттенком материала) -----------------

        static Color Cloth(float u, float v)
        {
            // Полотняное переплетение: нити по очереди сверху и снизу.
            int tx = Mathf.FloorToInt(u * 128f), ty = Mathf.FloorToInt(v * 128f);
            float fx = u * 128f - tx, fy = v * 128f - ty;
            bool warp = ((tx + ty) & 1) == 0;
            float thread = warp ? Mathf.Sin(fx * Mathf.PI) : Mathf.Sin(fy * Mathf.PI);
            float g = 0.72f + thread * 0.2f + (Fbm(u, v, 8, 3, 111) - 0.5f) * 0.15f;
            return new Color(g, g, g);
        }

        static Color Leather(float u, float v)
        {
            float n = Fbm(u, v, 8, 5, 121);
            float f1, f2, id;
            Voronoi(u, v, 48, 122, out f1, out f2, out id);
            float crease = Mathf.Clamp01((f2 - f1) * 8f);
            var c = Mix(new Color(0.30f, 0.19f, 0.11f), new Color(0.50f, 0.34f, 0.20f), n);
            return Shade(c, 0.8f + crease * 0.2f);
        }

        static Color Skin(float u, float v)
        {
            float g = 0.88f + (Fbm(u, v, 8, 4, 131) - 0.5f) * 0.12f;
            return new Color(g, g, g);
        }

        static Color Fur(float u, float v)
        {
            float hair = Value2(u, v, 192, 16, 141) * 0.6f + Value2(u, v, 96, 14, 142) * 0.4f;
            float g = 0.62f + hair * 0.3f + (Fbm(u, v, 4, 3, 143) - 0.5f) * 0.2f;
            return new Color(g, g, g);
        }

        /// Руда: порода и вкрапления — золото, ржавое железо, уголь, камень.
        static Color Ore(float u, float v, Color rock, Color vein, int seed)
        {
            var c = Mix(Shade(rock, 0.75f), Shade(rock, 1.15f), Fbm(u, v, 5, 5, seed));
            float f1, f2, id;
            Voronoi(u, v, 20, seed + 1, out f1, out f2, out id);
            if (id > 0.6f && f1 < 0.3f) c = Mix(c, vein, (1f - f1 / 0.3f) * 1.2f);
            float crack = Mathf.Clamp01((f2 - f1) * 5f);
            return Shade(c, 0.7f + 0.3f * crack);
        }
    }
}
