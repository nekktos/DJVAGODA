// Модели построек — свои, кодом (решение автора от 02.10). Размер — из
// ядра (Res.BuildingSize), вход — с фасада (+z). Ступень укрепления видна по
// стенам (ответ автора от 29.09: дерево → дерево и камень → камень → камень
// и железо): низ, верх и окантовка меняют материал.
//
// Недостроенная постройка — основание, леса по углам и стены по пояс без
// крыши: стены растут с ходом стройки (BuildingActor.ShowProgress), крыша
// появляется, когда достроено.
using DjvaGoda.Core;
using UnityEngine;

namespace DjvaGoda.Game
{
    public static class BuildingShapes
    {
        /// Узел стен — его высоту тянет стройка.
        public const string WallsName = "Стены";

        static Mesh _cube, _prism, _cylinder;

        static Mesh Cube()
        {
            if (_cube == null)
            {
                var go = GameObject.CreatePrimitive(PrimitiveType.Cube);
                _cube = go.GetComponent<MeshFilter>().sharedMesh;
                Object.Destroy(go);
            }
            return _cube;
        }

        static Mesh Cylinder()
        {
            if (_cylinder == null)
                _cylinder = BodyShapes.Loft("цилиндр", new[] { new BodyShapes.Ring(-0.5f, 0.5f, 0.5f), new BodyShapes.Ring(0.5f, 0.5f, 0.5f) }, 12);
            return _cylinder;
        }

        /// Двускатная крыша: треугольник в сечении (x от −0.5 до 0.5, y от 0 до 1),
        /// протянутый по z от −0.5 до 0.5; щипцы закрыты.
        public static Mesh Prism()
        {
            if (_prism != null) return _prism;
            var v = new[]
            {
                // Левый скат.
                new Vector3(-0.5f, 0f, -0.5f), new Vector3(0f, 1f, -0.5f), new Vector3(0f, 1f, 0.5f), new Vector3(-0.5f, 0f, 0.5f),
                // Правый скат.
                new Vector3(0.5f, 0f, 0.5f), new Vector3(0f, 1f, 0.5f), new Vector3(0f, 1f, -0.5f), new Vector3(0.5f, 0f, -0.5f),
                // Щипцы.
                new Vector3(-0.5f, 0f, 0.5f), new Vector3(0f, 1f, 0.5f), new Vector3(0.5f, 0f, 0.5f),
                new Vector3(0.5f, 0f, -0.5f), new Vector3(0f, 1f, -0.5f), new Vector3(-0.5f, 0f, -0.5f),
            };
            // Обход по часовой, если смотреть снаружи: лицевая сторона в Unity.
            var t = new[] { 0, 2, 1, 0, 3, 2, 4, 6, 5, 4, 7, 6, 8, 10, 9, 11, 13, 12 };
            _prism = new Mesh { name = "призма" };
            _prism.vertices = v;
            _prism.triangles = t;
            _prism.RecalculateNormals();
            _prism.RecalculateBounds();
            return _prism;
        }

        static Transform Part(Transform parent, string name, Mesh mesh, string material, Vector3 at, Vector3 scale, float yaw = 0f)
        {
            var go = new GameObject(name);
            go.transform.SetParent(parent, false);
            go.transform.localPosition = at;
            go.transform.localScale = scale;
            if (yaw != 0f) go.transform.localRotation = Quaternion.Euler(0f, yaw, 0f);
            go.AddComponent<MeshFilter>().sharedMesh = mesh;
            go.AddComponent<MeshRenderer>().sharedMaterial = Palette.Of(material);
            return go.transform;
        }

        static Transform Box(Transform parent, string name, string material, Vector3 at, Vector3 size, float yaw = 0f)
        {
            return Part(parent, name, Cube(), material, at, size, yaw);
        }

        static Transform Post(Transform parent, string material, Vector3 at, float height, float radius)
        {
            return Part(parent, "Столб", Cylinder(), material, at + new Vector3(0f, height * 0.5f, 0f), new Vector3(radius * 2f, height, radius * 2f));
        }

        /// Материалы ступени: низ, верх, окантовка.
        static void GradeMaterials(int grade, out string lower, out string upper, out string trim)
        {
            lower = grade >= 1 ? "stone" : "wood";
            upper = grade >= 2 ? "stone" : "wood";
            trim = grade >= 3 ? "dark_metal" : "wood";
        }

        /// Собрать модель под корнем. done — с крышей; иначе стройка с лесами.
        public static Transform Build(Transform parent, BuildingKind kind, int grade, Faction side, bool done)
        {
            var root = new GameObject("Вид").transform;
            root.SetParent(parent, false);
            var size = Res.BuildingSize(kind).ToUnity();
            switch (kind)
            {
                case BuildingKind.Farm: Farm(root, size, done); break;
                case BuildingKind.ElfHouse:
                case BuildingKind.ElfStoneHouse: ElfHouse(root, size, kind == BuildingKind.ElfStoneHouse, done); break;
                default: Hall(root, kind, grade, side, size, done); break;
            }
            if (!Res.Walkable(kind))
            {
                var box = root.gameObject.AddComponent<BoxCollider>();
                box.center = new Vector3(0f, size.y * 0.5f, 0f);
                box.size = size;
            }
            return root;
        }

        /// Срубы людей и злодея: стены по ступени, двускатная крыша, дверь
        /// с фасада, окна, угловые столбы; у каждого вида — свои приметы.
        static void Hall(Transform root, BuildingKind kind, int grade, Faction side, Vector3 size, bool done)
        {
            string lower, upper, trim;
            GradeMaterials(grade, out lower, out upper, out trim);
            float wallH = size.y * 0.58f, roofH = size.y - wallH;
            float w = size.x, d = size.z;
            Box(root, "Основание", "stone", new Vector3(0f, 0.2f, 0f), new Vector3(w + 0.4f, 0.4f, d + 0.4f));
            var walls = new GameObject(WallsName).transform;
            walls.SetParent(root, false);
            Box(walls, "Низ стен", lower, new Vector3(0f, wallH * 0.25f, 0f), new Vector3(w, wallH * 0.5f, d));
            Box(walls, "Верх стен", upper, new Vector3(0f, wallH * 0.75f, 0f), new Vector3(w - 0.1f, wallH * 0.5f, d - 0.1f));
            for (int sx = -1; sx <= 1; sx += 2)
                for (int sz = -1; sz <= 1; sz += 2)
                    Box(walls, "Угол", trim, new Vector3((w * 0.5f) * sx, wallH * 0.5f, (d * 0.5f) * sz), new Vector3(0.35f, wallH, 0.35f));
            // Дверь и окна — тёмные вставки чуть наружу.
            Box(walls, "Дверь", "dark_stone", new Vector3(0f, 1.1f, d * 0.5f + 0.03f), new Vector3(1.6f, 2.2f, 0.1f));
            Box(walls, "Притолока", trim, new Vector3(0f, 2.3f, d * 0.5f + 0.06f), new Vector3(2f, 0.2f, 0.12f));
            int windows = Mathf.Max(1, Mathf.FloorToInt(w / 5f));
            for (int i = 0; i < windows; i++)
            {
                float x = (i + 0.5f) / windows * w - w * 0.5f;
                if (Mathf.Abs(x) < 1.6f) continue;
                Box(walls, "Окно", "dark_stone", new Vector3(x, wallH * 0.62f, d * 0.5f + 0.03f), new Vector3(0.9f, 0.9f, 0.08f));
                Box(walls, "Окно сзади", "dark_stone", new Vector3(x, wallH * 0.62f, -d * 0.5f - 0.03f), new Vector3(0.9f, 0.9f, 0.08f));
            }
            if (!done)
            {
                Scaffold(root, w, d, wallH);
                return;
            }
            string roofMaterial = kind == BuildingKind.Storage || kind == BuildingKind.ArcherBarracks || kind == BuildingKind.Stable ? "thatch" : "roof";
            if (side == Faction.Villain && roofMaterial == "roof") roofMaterial = "dark_stone";
            // Конёк вдоль длинной стороны.
            bool alongX = w >= d;
            Part(root, "Крыша", Prism(), roofMaterial, new Vector3(0f, wallH, 0f),
                alongX ? new Vector3(d + 1.2f, roofH, w + 1.2f) : new Vector3(w + 1.2f, roofH, d + 1.2f), alongX ? 90f : 0f);
            Box(root, "Конёк", trim, new Vector3(0f, wallH + roofH, 0f), alongX ? new Vector3(w + 1.2f, 0.25f, 0.3f) : new Vector3(0.3f, 0.25f, d + 1.2f));
            // Знамя стороны у входа.
            Post(root, "wood", new Vector3(w * 0.5f - 0.6f, 0f, d * 0.5f + 1.2f), wallH + 1.5f, 0.08f);
            Box(root, "Знамя", "side_" + (int)side, new Vector3(w * 0.5f - 0.6f, wallH + 0.6f, d * 0.5f + 1.2f + 0.02f), new Vector3(0.9f, 1.6f, 0.05f));

            switch (kind)
            {
                case BuildingKind.Storage:
                    for (int i = 0; i < 4; i++)
                        Part(root, "Бочка", Cylinder(), "wood", new Vector3(-w * 0.5f + 1f + i * 1.1f, 0.6f, d * 0.5f + 1.1f), new Vector3(0.9f, 1.2f, 0.9f));
                    Box(root, "Ящик", "wood", new Vector3(-w * 0.5f + 1.2f, 0.5f, d * 0.5f + 2.4f), new Vector3(1f, 1f, 1f), 20f);
                    break;
                case BuildingKind.SwordBarracks:
                    // Стойка с мечами у входа.
                    Box(root, "Стойка", "wood", new Vector3(-w * 0.5f + 2f, 0.9f, d * 0.5f + 0.9f), new Vector3(2.4f, 0.12f, 0.3f));
                    for (int i = 0; i < 5; i++)
                        Box(root, "Меч", "metal", new Vector3(-w * 0.5f + 1.1f + i * 0.45f, 0.9f, d * 0.5f + 0.9f), new Vector3(0.07f, 1.4f, 0.03f));
                    break;
                case BuildingKind.ArcherBarracks:
                    // Мишень: соломенный круг с алым центром.
                    var target = Part(root, "Мишень", Cylinder(), "thatch", new Vector3(-w * 0.5f - 2f, 1.3f, d * 0.5f), new Vector3(1.6f, 0.25f, 1.6f));
                    target.localRotation = Quaternion.Euler(90f, 0f, 0f);
                    var bull = Part(root, "Яблочко", Cylinder(), "accent", new Vector3(-w * 0.5f - 2f, 1.3f, d * 0.5f + 0.14f), new Vector3(0.5f, 0.05f, 0.5f));
                    bull.localRotation = Quaternion.Euler(90f, 0f, 0f);
                    break;
                case BuildingKind.Stable:
                    // Загон с изгородью и стог сена.
                    for (int i = 0; i <= 4; i++)
                        Post(root, "wood", new Vector3(-w * 0.5f + i * w / 4f, 0f, d * 0.5f + 4f), 1.3f, 0.09f);
                    Box(root, "Жердь", "wood", new Vector3(0f, 1.0f, d * 0.5f + 4f), new Vector3(w, 0.12f, 0.12f));
                    Box(root, "Жердь", "wood", new Vector3(0f, 0.55f, d * 0.5f + 4f), new Vector3(w, 0.12f, 0.12f));
                    Part(root, "Стог", BodyShapes.Dome(), "thatch", new Vector3(w * 0.5f + 1.8f, 0f, 0f), new Vector3(2.6f, 2.6f, 2.6f));
                    break;
                case BuildingKind.House:
                    Box(root, "Труба", "stone", new Vector3(w * 0.25f, wallH + roofH * 0.7f, -d * 0.15f), new Vector3(0.8f, roofH * 1.1f, 0.8f));
                    break;
                case BuildingKind.Forge:
                    Box(root, "Горн", "stone", new Vector3(w * 0.3f, wallH + roofH * 0.6f, 0f), new Vector3(1.2f, roofH * 1.6f, 1.2f));
                    // Навес с наковальней и тлеющими углями.
                    Box(root, "Навес", "wood", new Vector3(0f, wallH * 0.7f, d * 0.5f + 1.6f), new Vector3(w * 0.7f, 0.15f, 3.2f));
                    for (int s = -1; s <= 1; s += 2)
                        Post(root, "wood", new Vector3(w * 0.33f * s, 0f, d * 0.5f + 3f), wallH * 0.7f, 0.1f);
                    Box(root, "Наковальня", "dark_metal", new Vector3(-1f, 0.6f, d * 0.5f + 1.6f), new Vector3(0.9f, 0.35f, 0.4f));
                    Box(root, "Колода", "wood", new Vector3(-1f, 0.25f, d * 0.5f + 1.6f), new Vector3(0.6f, 0.5f, 0.6f));
                    Box(root, "Угли", "accent", new Vector3(1.4f, 0.55f, d * 0.5f + 1.2f), new Vector3(1f, 0.25f, 0.8f));
                    break;
            }
        }

        /// Леса стройки: столбы по углам и посередине, перекладины на уровне стен.
        static void Scaffold(Transform root, float w, float d, float wallH)
        {
            float h = wallH + 0.8f;
            for (int sx = -1; sx <= 1; sx++)
                for (int sz = -1; sz <= 1; sz += 2)
                    Post(root, "wood", new Vector3((w * 0.5f + 0.6f) * sx, 0f, (d * 0.5f + 0.6f) * sz), h, 0.07f);
            for (int sz = -1; sz <= 1; sz += 2)
            {
                Box(root, "Настил", "wood", new Vector3(0f, wallH * 0.5f, (d * 0.5f + 0.6f) * sz), new Vector3(w + 1.3f, 0.08f, 0.5f));
                Box(root, "Перекладина", "wood", new Vector3(0f, h - 0.1f, (d * 0.5f + 0.6f) * sz), new Vector3(w + 1.3f, 0.1f, 0.1f));
            }
        }

        /// Поле: вспаханная земля рядами, посевы, межевые колья.
        static void Farm(Transform root, Vector3 size, bool done)
        {
            Box(root, "Пашня", "road", new Vector3(0f, 0.05f, 0f), new Vector3(size.x, 0.1f, size.z));
            int rows = Mathf.Max(2, Mathf.FloorToInt(size.z / 1.6f));
            for (int r = 0; r < rows; r++)
            {
                float z = (r + 0.5f) / rows * size.z - size.z * 0.5f;
                Box(root, "Борозда", "road", new Vector3(0f, 0.16f, z), new Vector3(size.x - 0.6f, 0.14f, 0.5f));
                if (!done) continue;
                // Колосья — снопиками вдоль борозды.
                int tufts = Mathf.FloorToInt(size.x / 1.2f);
                for (int i = 0; i < tufts; i++)
                {
                    float x = (i + 0.5f) / tufts * (size.x - 1f) - (size.x - 1f) * 0.5f;
                    Part(root, "Колосья", BodyShapes.Cone(6), "thatch", new Vector3(x, 0.2f, z), new Vector3(0.45f, 0.8f, 0.45f));
                }
            }
            for (int sx = -1; sx <= 1; sx += 2)
                for (int sz = -1; sz <= 1; sz += 2)
                    Post(root, "wood", new Vector3(size.x * 0.5f * sx, 0f, size.z * 0.5f * sz), 1.2f, 0.07f);
        }

        /// Дом эльфов: круглый, стены — живые стволы (или камень у каменного),
        /// крыша — конус листвы, круглая дверь.
        static void ElfHouse(Transform root, Vector3 size, bool stone, bool done)
        {
            float r = Mathf.Min(size.x, size.z) * 0.45f;
            float wallH = size.y * 0.5f, roofH = size.y - wallH + 1.5f;
            var walls = new GameObject(WallsName).transform;
            walls.SetParent(root, false);
            Part(walls, "Стена", Cylinder(), stone ? "stone" : "bark", new Vector3(0f, wallH * 0.5f, 0f), new Vector3(r * 2f, wallH, r * 2f));
            // Стволы-опоры по кругу.
            for (int i = 0; i < 8; i++)
            {
                float a = i * Mathf.PI * 2f / 8f;
                Post(walls, "bark", new Vector3(Mathf.Sin(a) * r, 0f, Mathf.Cos(a) * r), wallH + 0.6f, 0.28f);
            }
            var door = Part(walls, "Дверь", Cylinder(), "dark_stone", new Vector3(0f, 1.3f, r + 0.02f), new Vector3(1.6f, 0.1f, 2.4f));
            door.localRotation = Quaternion.Euler(90f, 0f, 0f);
            if (!done) return;
            Part(root, "Крыша", BodyShapes.Cone(14), "foliage", new Vector3(0f, wallH - 0.2f, 0f), new Vector3(r * 2.8f, roofH, r * 2.8f));
            Part(root, "Верхушка", BodyShapes.Cone(10), "needles", new Vector3(0f, wallH + roofH * 0.55f, 0f), new Vector3(r * 1.4f, roofH * 0.7f, r * 1.4f));
        }
    }
}
