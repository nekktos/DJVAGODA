// Отделка мира поверх кусков плана (решение автора от 02.10: модели — свои).
// Кусок плана остаётся формой и коллизией; отделка — без коллизий, отдельным
// узлом в мировых координатах (не наследует растянутый масштаб куска):
//   wall — зубцы поверху; palace_wall — зубцы и ряды окон;
//   tower:крыша — зубчатый венец и конус крыши; keep — зубцы, бойницы, знамя;
//   house:крыша — двускатная крыша, дверь, окна; trader — товар на прилавке;
//   bench — инструменты и протезы; well — сруб с навесом и ведром;
//   mine_rock — глыбы, ломающие кубический силуэт; mine_door — крепь входа
//   и рельсы; ore — россыпь руды.
using DjvaGoda.Core;
using UnityEngine;

namespace DjvaGoda.Game
{
    public static class WorldDetail
    {
        static Mesh _cube, _cylinder;

        static Mesh Cube()
        {
            if (_cube == null)
            {
                var go = GameObject.CreatePrimitive(PrimitiveType.Cube);
                _cube = go.GetComponent<MeshFilter>().sharedMesh;
                Object.DestroyImmediate(go);
            }
            return _cube;
        }

        static Mesh Cylinder()
        {
            if (_cylinder == null)
                _cylinder = BodyShapes.Loft("цилиндр", new[] { new BodyShapes.Ring(-0.5f, 0.5f, 0.5f), new BodyShapes.Ring(0.5f, 0.5f, 0.5f) }, 12);
            return _cylinder;
        }

        static Transform Part(Transform parent, string name, Mesh mesh, string material, Vector3 at, Vector3 scale, Quaternion? rotation = null)
        {
            var go = new GameObject(name);
            go.transform.SetParent(parent, false);
            go.transform.localPosition = at;
            go.transform.localScale = scale;
            if (rotation.HasValue) go.transform.localRotation = rotation.Value;
            go.AddComponent<MeshFilter>().sharedMesh = mesh;
            go.AddComponent<MeshRenderer>().sharedMaterial = Palette.Of(material);
            return go.transform;
        }

        static Transform Box(Transform parent, string name, string material, Vector3 at, Vector3 size, Quaternion? rotation = null)
        {
            return Part(parent, name, Cube(), material, at, size, rotation);
        }

        /// Отделка куска или null. Узел — в центре куска с его поворотом, масштаб 1.
        public static GameObject Decorate(Piece piece, Transform parent)
        {
            if (string.IsNullOrEmpty(piece.Detail)) return null;
            string kind = piece.Detail, arg = null;
            int colon = kind.IndexOf(':');
            if (colon >= 0)
            {
                arg = kind.Substring(colon + 1);
                kind = kind.Substring(0, colon);
            }
            var root = new GameObject("Отделка: " + piece.Detail).transform;
            root.SetParent(parent, false);
            root.SetPositionAndRotation(piece.Center.ToUnity(), CoreSpace.YawToRotation(piece.Yaw));
            var size = piece.Size.ToUnity();
            string material = piece.Material;
            switch (kind)
            {
                case "wall": Battlements(root, size, material); break;
                case "palace_wall": Battlements(root, size, material); Windows(root, size, 6f, "dark_stone"); break;
                case "tower": Tower(root, size, material, arg ?? "roof"); break;
                case "keep": Keep(root, size, material); break;
                case "house": House(root, size, arg ?? "roof"); break;
                case "trader": Trader(root, size); break;
                case "bench": Bench(root, size); break;
                case "well": Well(root, size); break;
                case "mine_rock": MineRock(root, size, Mathf.Abs((int)(piece.Center.X * 13f + piece.Center.Z * 7f)) % 997); break;
                case "mine_door": MineDoor(root, size); break;
                case "ore": Ore(root, size, material); break;
            }
            return root.gameObject;
        }

        /// Зубцы по верху стены вдоль длинной стороны: через одного, как у крепости.
        static void Battlements(Transform root, Vector3 size, string material)
        {
            bool alongX = size.x >= size.z;
            float length = alongX ? size.x : size.z, thick = alongX ? size.z : size.x;
            int count = Mathf.Max(2, Mathf.FloorToInt(length / 3.2f));
            float step = length / count;
            float top = size.y * 0.5f;
            for (int i = 0; i < count; i += 2)
            {
                float t = -length * 0.5f + (i + 0.5f) * step;
                var at = alongX ? new Vector3(t, top + 0.7f, 0f) : new Vector3(0f, top + 0.7f, t);
                var merlon = alongX ? new Vector3(step, 1.4f, thick + 0.2f) : new Vector3(thick + 0.2f, 1.4f, step);
                Box(root, "Зубец", material, at, merlon);
            }
            // Карниз: тонкий выступ под зубцами.
            Box(root, "Карниз", material, new Vector3(0f, top - 0.2f, 0f), alongX ? new Vector3(length, 0.4f, thick + 0.5f) : new Vector3(thick + 0.5f, 0.4f, length));
        }

        /// Ряды окон по длинным граням: тёмные проёмы с подоконником.
        static void Windows(Transform root, Vector3 size, float spacing, string material)
        {
            bool alongX = size.x >= size.z;
            float length = alongX ? size.x : size.z, thick = alongX ? size.z : size.x;
            int cols = Mathf.Max(1, Mathf.FloorToInt(length / spacing));
            int rows = Mathf.Max(1, Mathf.FloorToInt(size.y / 8f));
            for (int r = 0; r < rows; r++)
                for (int c = 0; c < cols; c++)
                {
                    float t = -length * 0.5f + (c + 0.5f) * length / cols;
                    float y = -size.y * 0.5f + (r + 0.6f) * size.y / rows;
                    for (int s = -1; s <= 1; s += 2)
                    {
                        var at = alongX ? new Vector3(t, y, s * (thick * 0.5f + 0.02f)) : new Vector3(s * (thick * 0.5f + 0.02f), y, t);
                        var win = alongX ? new Vector3(1.4f, 2.6f, 0.1f) : new Vector3(0.1f, 2.6f, 1.4f);
                        Box(root, "Окно", material, at, win);
                    }
                }
        }

        /// Башня: зубчатый венец по окружности и конус крыши над ним.
        static void Tower(Transform root, Vector3 size, string material, string roof)
        {
            float r = size.x, top = size.y * 0.5f;
            Part(root, "Венец", Cylinder(), material, new Vector3(0f, top + 0.3f, 0f), new Vector3(r * 2f + 1f, 0.6f, r * 2f + 1f));
            int count = Mathf.Max(8, Mathf.RoundToInt(2f * Mathf.PI * r / 3f));
            for (int i = 0; i < count; i += 2)
            {
                float a = i * Mathf.PI * 2f / count;
                var at = new Vector3(Mathf.Sin(a) * (r + 0.2f), top + 1.3f, Mathf.Cos(a) * (r + 0.2f));
                Box(root, "Зубец", material, at, new Vector3(2.4f, 1.4f, 1f), Quaternion.Euler(0f, a * Mathf.Rad2Deg, 0f));
            }
            // Бойницы по кругу.
            for (int i = 0; i < 6; i++)
            {
                float a = (i + 0.5f) * Mathf.PI * 2f / 6f;
                Box(root, "Бойница", "dark_metal", new Vector3(Mathf.Sin(a) * (r + 0.03f), 0f, Mathf.Cos(a) * (r + 0.03f)), new Vector3(0.5f, 2.2f, 0.1f),
                    Quaternion.Euler(0f, a * Mathf.Rad2Deg, 0f));
            }
            Part(root, "Крыша", BodyShapes.Cone(16), roof, new Vector3(0f, top + 2f, 0f), new Vector3(r * 2.2f, r * 1.3f, r * 2.2f));
        }

        /// Донжон: зубцы по всем четырём краям крыши, бойницы на всех гранях, знамя злодея.
        static void Keep(Transform root, Vector3 size, string material)
        {
            for (int s = -1; s <= 1; s += 2)
            {
                Node(root, new Vector3(0f, 0f, s * (size.z * 0.5f - 1f)), 0f, n => Battlements(n, new Vector3(size.x, size.y, 2f), material));
                Node(root, new Vector3(s * (size.x * 0.5f - 1f), 0f, 0f), 0f, n => Battlements(n, new Vector3(2f, size.y, size.z), material));
            }
            Windows(root, size, 8f, "dark_metal");
            Node(root, Vector3.zero, 90f, n => Windows(n, new Vector3(size.z, size.y, size.x), 8f, "dark_metal"));
            Part(root, "Древко", Cylinder(), "dark_metal", new Vector3(0f, size.y * 0.5f + 6f, 0f), new Vector3(0.4f, 12f, 0.4f));
            Box(root, "Знамя", "side_0", new Vector3(2.5f, size.y * 0.5f + 9.5f, 0f), new Vector3(5f, 4f, 0.15f));
        }

        static void Node(Transform root, Vector3 at, float yaw, System.Action<Transform> fill)
        {
            var node = new GameObject("Грань").transform;
            node.SetParent(root, false);
            node.localPosition = at;
            node.localRotation = Quaternion.Euler(0f, yaw, 0f);
            fill(node);
        }

        /// Дом: двускатная крыша по длинной стороне, дверь, окна.
        static void House(Transform root, Vector3 size, string roof)
        {
            bool alongX = size.x >= size.z;
            float top = size.y * 0.5f, roofH = Mathf.Max(2f, Mathf.Min(size.x, size.z) * 0.45f);
            Part(root, "Крыша", BuildingShapes.Prism(), roof, new Vector3(0f, top, 0f),
                alongX ? new Vector3(size.z + 1f, roofH, size.x + 1f) : new Vector3(size.x + 1f, roofH, size.z + 1f),
                Quaternion.Euler(0f, alongX ? 90f : 0f, 0f));
            float front = (alongX ? size.z : size.x) * 0.5f + 0.03f;
            var doorAt = alongX ? new Vector3(0f, -top + 1.1f, front) : new Vector3(front, -top + 1.1f, 0f);
            Box(root, "Дверь", "dark_stone", doorAt, alongX ? new Vector3(1.4f, 2.2f, 0.08f) : new Vector3(0.08f, 2.2f, 1.4f));
            float length = alongX ? size.x : size.z;
            for (int s = -1; s <= 1; s += 2)
            {
                float t = s * length * 0.3f;
                var at = alongX ? new Vector3(t, 0.3f, front) : new Vector3(front, 0.3f, t);
                Box(root, "Окно", "dark_stone", at, alongX ? new Vector3(1f, 1f, 0.08f) : new Vector3(0.08f, 1f, 1f));
            }
        }

        /// Прилавок: бочки, мешки, ящики и связка стрел — видно, что здесь торгуют.
        static void Trader(Transform root, Vector3 size)
        {
            float top = size.y * 0.5f;
            var e = BodyShapes.Ellipsoid();
            for (int i = 0; i < 3; i++)
                Part(root, "Мешок", e, "linen", new Vector3(-2.4f + i * 0.9f, top + 0.3f, 0.6f), new Vector3(0.8f, 0.6f, 0.6f));
            Box(root, "Ящик", "wood", new Vector3(0.6f, top + 0.35f, 0.4f), new Vector3(0.7f, 0.7f, 0.7f), Quaternion.Euler(0f, 15f, 0f));
            Box(root, "Слиток", "gold", new Vector3(1.6f, top + 0.12f, 0.8f), new Vector3(0.4f, 0.2f, 0.25f));
            Box(root, "Слиток", "metal", new Vector3(2.1f, top + 0.12f, 0.6f), new Vector3(0.4f, 0.2f, 0.25f));
            for (int i = 0; i < 2; i++)
                Part(root, "Бочка", Cylinder(), "wood", new Vector3(-3.6f + i * 7.2f, -top + 0.6f, 2.8f), new Vector3(1f, 1.2f, 1f));
            for (int i = 0; i < 5; i++)
                Box(root, "Стрела", "wood", new Vector3(2.8f, top + 0.6f, -0.4f + i * 0.08f), new Vector3(0.03f, 1.2f, 0.03f), Quaternion.Euler(0f, 0f, 8f));
        }

        /// Верстак-медпункт: инструменты на столе, протезы на крюках.
        static void Bench(Transform root, Vector3 size)
        {
            float top = size.y * 0.5f;
            Box(root, "Пила", "metal", new Vector3(-1.5f, top + 0.05f, 0.3f), new Vector3(1.2f, 0.03f, 0.25f));
            Box(root, "Молоток", "dark_metal", new Vector3(0.2f, top + 0.08f, -0.2f), new Vector3(0.35f, 0.12f, 0.12f));
            Box(root, "Доска", "wood", new Vector3(1.4f, top + 0.06f, 0.2f), new Vector3(1.4f, 0.1f, 0.4f));
            // Деревянные ноги и железная рука на стойке.
            Box(root, "Стойка", "wood", new Vector3(3.4f, 0f, 0f), new Vector3(0.2f, size.y + 1.6f, 0.2f));
            Box(root, "Перекладина", "wood", new Vector3(3.4f, top + 0.7f, 0f), new Vector3(0.2f, 0.15f, 2f));
            for (int i = 0; i < 3; i++)
            {
                string mat = i == 2 ? "metal" : "wood";
                Part(root, "Протез", BodyShapes.Loft("протез на крюке", new[] { new BodyShapes.Ring(0f, 0.06f, 0.06f), new BodyShapes.Ring(-0.8f, 0.03f, 0.03f) }, 6),
                    mat, new Vector3(3.4f, top + 0.6f, -0.7f + i * 0.7f), Vector3.one);
            }
        }

        /// Колодец: каменный сруб (сам кусок), столбы, навес и ведро.
        static void Well(Transform root, Vector3 size)
        {
            float r = size.x, top = size.y * 0.5f;
            for (int s = -1; s <= 1; s += 2)
                Box(root, "Столб", "wood", new Vector3(s * (r - 0.2f), top + 1f, 0f), new Vector3(0.2f, 2.6f, 0.2f));
            Box(root, "Ворот", "wood", new Vector3(0f, top + 1.6f, 0f), new Vector3(r * 2f, 0.15f, 0.15f));
            Part(root, "Навес", BuildingShapes.Prism(), "thatch", new Vector3(0f, top + 2.3f, 0f), new Vector3(r * 2.4f, 1f, r * 1.8f));
            Part(root, "Ведро", Cylinder(), "wood", new Vector3(0.3f, top + 0.9f, 0f), new Vector3(0.4f, 0.4f, 0.4f));
        }

        /// Глыба шахты: крупные валуны по вертикальным рёбрам, бокам и макушке
        /// прячут кубический силуэт; фасад со входом (−z) открыт.
        static void MineRock(Transform root, Vector3 size, int seed)
        {
            var rng = new System.Random(seed + 17);
            float hx = size.x * 0.5f, hy = size.y * 0.5f, hz = size.z * 0.5f;
            int n = 0;
            System.Action<Vector3, float> boulder = (at, s) =>
            {
                float a = (float)(rng.NextDouble() * 360.0);
                Part(root, "Валун", Shapes.Rock(seed * 31 + n++), "rock", at, new Vector3(s, s * 0.75f, s * 0.9f) * 0.5f, Quaternion.Euler(0f, a, 0f));
            };
            // Рёбра: по два валуна на каждом (низ и верх).
            for (int sx = -1; sx <= 1; sx += 2)
                for (int sz = -1; sz <= 1; sz += 2)
                {
                    boulder(new Vector3(sx * hx, -hy + 4f, sz * hz), 14f + (float)rng.NextDouble() * 4f);
                    boulder(new Vector3(sx * hx * 0.9f, hy - 1f, sz * hz * 0.9f), 12f + (float)rng.NextDouble() * 4f);
                }
            // Бока и спина — по валуну посередине.
            boulder(new Vector3(-hx, 0f, 0f), 16f);
            boulder(new Vector3(hx, 0f, 0f), 16f);
            boulder(new Vector3(0f, 0f, hz), 18f);
            // Макушка.
            for (int i = 0; i < 3; i++)
                boulder(new Vector3(((float)rng.NextDouble() - 0.5f) * size.x * 0.5f, hy + 1.5f, ((float)rng.NextDouble() - 0.2f) * size.z * 0.5f),
                    16f + (float)rng.NextDouble() * 6f);
        }

        /// Вход в шахту: тёмный проём (сам кусок) в деревянной крепи и рельсы наружу.
        static void MineDoor(Transform root, Vector3 size)
        {
            float half = size.x * 0.5f, top = size.y * 0.5f, face = -size.z * 0.5f - 0.3f;
            for (int s = -1; s <= 1; s += 2)
                Box(root, "Стойка крепи", "wood", new Vector3(s * (half * 0.55f), 0f, face), new Vector3(0.6f, size.y, 0.6f));
            Box(root, "Верхняк", "wood", new Vector3(0f, top - 0.4f, face), new Vector3(size.x * 0.7f, 0.7f, 0.7f));
            for (int s = -1; s <= 1; s += 2)
                Box(root, "Рельс", "dark_metal", new Vector3(s * 0.6f, -top + 0.08f, face - 4f), new Vector3(0.12f, 0.12f, 8f));
            for (int i = 0; i < 8; i++)
                Box(root, "Шпала", "wood", new Vector3(0f, -top + 0.03f, face - 0.5f - i), new Vector3(1.8f, 0.08f, 0.25f));
            Part(root, "Фонарь", BodyShapes.Ellipsoid(), "dark_metal", new Vector3(half * 0.55f, top * 0.4f, face - 0.4f), new Vector3(0.3f, 0.4f, 0.3f))
                .GetComponent<MeshRenderer>().sharedMaterial = Palette.Glow("fire");
        }

        /// Куча руды: россыпь комьев той же руды вокруг куска.
        static void Ore(Transform root, Vector3 size, string material)
        {
            var rng = new System.Random(material.GetHashCode());
            for (int i = 0; i < 10; i++)
            {
                float a = (float)(rng.NextDouble() * Mathf.PI * 2f);
                float d = (float)rng.NextDouble() * size.x * 0.7f;
                float s = 0.6f + (float)rng.NextDouble() * 0.9f;
                Part(root, "Ком", Shapes.Rock(i + 7), material, new Vector3(Mathf.Sin(a) * d, -size.y * 0.5f + s * 0.25f + (i < 3 ? size.y * 0.6f : 0f), Mathf.Cos(a) * d),
                    new Vector3(s, s * 0.7f, s) * 0.5f);
            }
        }
    }
}
