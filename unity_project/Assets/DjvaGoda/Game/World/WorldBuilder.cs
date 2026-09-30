// Строит мир из плана ядра (шаг 5 «Мир»): рельеф, серые примитивы, лес.
//
// Мир строится одинаково на хосте и у клиентов из зерна — по сети он не
// едет. Сетевое в нём — только поваленные деревья и выбитые камни.
using System.Collections.Generic;
using DjvaGoda.Core;
using UnityEngine;

namespace DjvaGoda.Game
{
    /// Что можно добывать: дерево плана, камень, золото. У деревьев леса — номер.
    public class Harvestable : MonoBehaviour
    {
        public ResourceKind Resource;
        public int HitsLeft;
        /// Номер дерева леса эльфов; −1 — не из леса.
        public int TreeIndex = -1;
    }

    public class WorldBuilder : MonoBehaviour
    {
        public Relief Relief { get; private set; }
        public WorldPlan Plan { get; private set; }
        public Forest Forest { get; private set; }
        readonly Dictionary<int, GameObject> _trees = new Dictionary<int, GameObject>();

        /// Слой мира: по нему бьют лучи добычи и постановки.
        public const int WorldLayer = 0;

        void Awake()
        {
            Relief = DjvaGoda.Core.Relief.ForMap();
            Plan = WorldPlan.ForMap(Relief);
            Forest = DjvaGoda.Core.Forest.ForMap();
            BuildRelief();
            var groups = new Dictionary<string, Transform>();
            foreach (var piece in Plan.Pieces)
            {
                Transform parent;
                if (!groups.TryGetValue(piece.Group, out parent))
                {
                    parent = new GameObject(piece.Group).transform;
                    parent.SetParent(transform, false);
                    groups[piece.Group] = parent;
                }
                Place(piece, parent);
            }
            BuildForest();
        }

        void BuildRelief()
        {
            var go = new GameObject("Рельеф");
            go.transform.SetParent(transform, false);
            var mesh = Shapes.Relief(Relief, MapLayout.WorldSize);
            go.AddComponent<MeshFilter>().sharedMesh = mesh;
            var view = go.AddComponent<MeshRenderer>();
            view.sharedMaterial = Palette.Of("ground");
            // Рельеф теней не отбрасывает: самозатенение пологого полотна — «акне».
            view.shadowCastingMode = UnityEngine.Rendering.ShadowCastingMode.Off;
            go.AddComponent<MeshCollider>().sharedMesh = mesh;
            go.isStatic = true;
        }

        GameObject Place(Piece piece, Transform parent)
        {
            GameObject go;
            var at = piece.Center.ToUnity();
            var size = piece.Size.SizeToUnity();
            switch (piece.Shape)
            {
                case PieceShape.Box:
                    go = GameObject.CreatePrimitive(PrimitiveType.Cube);
                    go.transform.localScale = size;
                    go.transform.SetPositionAndRotation(at, CoreSpace.YawToRotation(piece.Yaw));
                    break;
                case PieceShape.Cylinder:
                    // Цилиндр Unity: радиус 0.5, высота 2.
                    go = GameObject.CreatePrimitive(PrimitiveType.Cylinder);
                    go.transform.localScale = new Vector3(size.x * 2f, size.y * 0.5f, size.x * 2f);
                    go.transform.position = at;
                    SolidCylinder(go);
                    break;
                case PieceShape.Cone:
                    go = Mesh("Конус", Shapes.Cone(), at, new Vector3(size.x, size.y, size.x), 0f, false);
                    break;
                case PieceShape.Ramp:
                    go = Ramp(piece);
                    break;
                case PieceShape.Peak:
                    go = Mesh("Вершина", Shapes.Peak(piece.ShapeSeed), at,
                        new Vector3(size.x * 0.5f, size.y, size.z * 0.5f), piece.Yaw, true);
                    break;
                case PieceShape.Rock:
                    go = Mesh("Валун", Shapes.Rock(piece.ShapeSeed), at, size * 0.5f, piece.Yaw, true);
                    break;
                default:
                    go = Tree(at, size.y);
                    break;
            }
            go.transform.SetParent(parent, true);
            var renderer = go.GetComponent<MeshRenderer>();
            if (renderer != null && piece.Shape != PieceShape.Tree) renderer.sharedMaterial = Palette.Of(piece.Material);
            if (piece.Decor)
            {
                var col = go.GetComponent<Collider>();
                if (col != null) Destroy(col);
            }
            if (piece.Harvest.HasValue)
            {
                var harvest = go.AddComponent<Harvestable>();
                harvest.Resource = piece.Harvest.Value;
                harvest.HitsLeft = piece.Hits;
            }
            go.isStatic = !piece.Harvest.HasValue;
            return go;
        }

        /// У цилиндра Unity коллайдер — капсула: башня 9×20 м стала бы пилюлей
        /// со скруглёнными боками. Меняем на выпуклый меш самого цилиндра.
        static void SolidCylinder(GameObject go)
        {
            var capsule = go.GetComponent<CapsuleCollider>();
            if (capsule != null) Destroy(capsule);
            var hull = go.AddComponent<MeshCollider>();
            hull.sharedMesh = go.GetComponent<MeshFilter>().sharedMesh;
            hull.convex = true;
        }

        static GameObject Mesh(string name, Mesh mesh, Vector3 at, Vector3 scale, float yaw, bool solid)
        {
            var go = new GameObject(name);
            go.AddComponent<MeshFilter>().sharedMesh = mesh;
            go.AddComponent<MeshRenderer>();
            go.transform.SetPositionAndRotation(at, CoreSpace.YawToRotation(yaw));
            go.transform.localScale = scale;
            if (solid) go.AddComponent<MeshCollider>().convex = true;
            return go;
        }

        /// Пандус на плато: наклонная плита с парапетами по бокам (без них с него падали).
        GameObject Ramp(Piece piece)
        {
            float width = piece.Size.X, rise = piece.Size.Y, run = piece.Size.Z;
            float length = Mathf.Sqrt(run * run + rise * rise);
            float pitch = Mathf.Atan2(rise, run) * Mathf.Rad2Deg;
            var root = new GameObject("Пандус");
            // Подножие у фасада (в ядре — больший z), подъём — к плато. После
            // отражения z плато лежит к +z Unity, и плиту наклоняем −pitch:
            // её дальний (+z) конец поднимается.
            var centre = (piece.Center + new V3(0f, rise * 0.5f, -run * 0.5f)).ToUnity();
            root.transform.SetPositionAndRotation(centre, Quaternion.Euler(-pitch, 0f, 0f));
            var slab = GameObject.CreatePrimitive(PrimitiveType.Cube);
            slab.name = "Плита";
            slab.transform.SetParent(root.transform, false);
            slab.transform.localScale = new Vector3(width, 2f, length);
            slab.GetComponent<MeshRenderer>().sharedMaterial = Palette.Of(piece.Material);
            for (int side = -1; side <= 1; side += 2)
            {
                var rail = GameObject.CreatePrimitive(PrimitiveType.Cube);
                rail.name = "Парапет";
                rail.transform.SetParent(root.transform, false);
                rail.transform.localPosition = new Vector3(side * (width * 0.5f + 0.5f), 0.5f, 0f);
                rail.transform.localScale = new Vector3(1f, 4f, length);
                rail.GetComponent<MeshRenderer>().sharedMaterial = Palette.Of(piece.Material);
            }
            return root;
        }

        /// Дерево-заглушка: ствол и конус кроны, коллизия — ствол.
        static GameObject Tree(Vector3 foot, float height)
        {
            var root = new GameObject("Дерево");
            root.transform.position = foot;
            var trunk = GameObject.CreatePrimitive(PrimitiveType.Cylinder);
            trunk.name = "Ствол";
            trunk.transform.SetParent(root.transform, false);
            float trunkHeight = height * 0.55f;
            trunk.transform.localPosition = new Vector3(0f, trunkHeight * 0.5f, 0f);
            trunk.transform.localScale = new Vector3(0.9f, trunkHeight * 0.5f, 0.9f);
            trunk.GetComponent<MeshRenderer>().sharedMaterial = Palette.Of("trunk");
            // Коллизия — во весь рост ствола и чуть шире: как у Godot-версии (радиус 1.1).
            var capsule = trunk.GetComponent<CapsuleCollider>();
            if (capsule != null) Destroy(capsule);
            var body = root.AddComponent<CapsuleCollider>();
            body.radius = 1.1f;
            body.height = height;
            body.center = new Vector3(0f, height * 0.5f, 0f);
            var crown = new GameObject("Крона");
            crown.transform.SetParent(root.transform, false);
            crown.AddComponent<MeshFilter>().sharedMesh = Shapes.Cone();
            crown.AddComponent<MeshRenderer>().sharedMaterial = Palette.Of("foliage");
            float crownHeight = height * 0.6f;
            crown.transform.localPosition = new Vector3(0f, height - crownHeight * 0.5f, 0f);
            crown.transform.localScale = new Vector3(height * 0.25f, crownHeight, height * 0.25f);
            return root;
        }

        /// Лес эльфов: деревья с номерами. Заглушкам хватает обычных объектов
        /// (1700 стволов PhysX держит); подгрузку по радиусам из ядра
        /// (Forest.CollectAround) включим, если профилировщик попросит.
        void BuildForest()
        {
            var holder = new GameObject("Лес эльфов").transform;
            holder.SetParent(transform, false);
            for (int i = 0; i < Forest.Count; i++)
            {
                var p = Forest.Positions[i];
                float height = Forest.CrownTop * Forest.Scales[i];
                var tree = Tree(new V3(p.X, Relief.Height(p.X, p.Z), p.Z).ToUnity(), height);
                tree.name = "Дерево " + i;
                tree.transform.SetParent(holder, true);
                var harvest = tree.AddComponent<Harvestable>();
                harvest.Resource = ResourceKind.Wood;
                harvest.HitsLeft = Res.SourceHits;
                harvest.TreeIndex = i;
                _trees[i] = tree;
            }
        }

        /// Повалить дерево леса (по сети приходит номер).
        public void Fell(int index)
        {
            Forest.Fell(index);
            GameObject tree;
            if (_trees.TryGetValue(index, out tree) && tree != null) Destroy(tree);
            _trees.Remove(index);
        }
    }
}
