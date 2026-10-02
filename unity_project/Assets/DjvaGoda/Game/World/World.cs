// Мир в сцене (шаг 5 «Мир»). Неподвижная часть — рельеф, крепости, гряды,
// камни — собирается в редакторе пунктом «ДжваГода → Собрать мир»
// (Editor/WorldBake) и хранится в сцене; сетка навигации запечена.
//
// Деревья — и лес эльфов, и рощи плана — в сцене не хранятся: их сажает этот
// компонент при загрузке, по зерну ядра, процедурными мешами (TreeShapes).
// 1700 деревьев раздували файл сцены до 8 МБ, а лес всё равно меняется в
// игре (рубка по номеру). В редакторе лес тоже виден: сажается без
// сохранения в сцену (HideFlags.DontSave).
//
// План мира остаётся в ядре: по нему считаются правила (рельеф под
// постройками, точки появления). Отпечаток плана в сцене ловит мир, не
// пересобранный после правки плана.
using System;

using System.Globalization;
using DjvaGoda.Core;
using UnityEngine;

namespace DjvaGoda.Game
{
    [ExecuteAlways]
    public class World : MonoBehaviour
    {
        const string ForestName = "Деревья (сажаются при загрузке)";

        /// Отпечаток плана, по которому собрана неподвижная часть мира.
        public string PlanPrint = "";

        public Relief Relief { get; private set; }
        public WorldPlan Plan { get; private set; }
        public Forest Forest { get; private set; }
        /// Деревья леса эльфов по номеру — по сети приходит номер.
        [NonSerialized] public GameObject[] Trees = new GameObject[0];
        Transform _holder;

        void OnEnable()
        {
            Relief = DjvaGoda.Core.Relief.ForMap();
            Plan = WorldPlan.ForMap(Relief);
            Forest = DjvaGoda.Core.Forest.ForMap();
            if (Application.isPlaying && PlanPrint != Print(Plan, Forest))
                Debug.LogError("Мир в сцене собран по старому плану: пересоберите (ДжваГода → Собрать мир).");
            Plant();
        }

        void OnDisable()
        {
            // В редакторе — убрать посаженное (перезагрузка скриптов, вход в
            // Play); в игре деревья уходят вместе со сценой.
            if (!Application.isPlaying) Unplant();
        }

        void Unplant()
        {
            for (int i = transform.childCount - 1; i >= 0; i--)
            {
                var child = transform.GetChild(i);
                if (child.name == ForestName) DestroyImmediate(child.gameObject);
            }
            _holder = null;
            Trees = new GameObject[0];
        }

        /// Посадить лес эльфов и рощи плана.
        public void Plant()
        {
            Unplant();
            bool editing = !Application.isPlaying;
            _holder = new GameObject(ForestName).transform;
            _holder.SetParent(transform, false);
            Trees = new GameObject[Forest.Count];
            for (int i = 0; i < Forest.Count; i++)
            {
                var p = Forest.Positions[i];
                var foot = new V3(p.X, Relief.Height(p.X, p.Z), p.Z);
                var tree = MakeTree("Дерево " + i, i, foot, Forest.Scales[i], Res.SourceHits, i);
                tree.GetComponent<Harvestable>().TreeIndex = i;
                Trees[i] = tree;
            }
            // Рощи плана (у дворца, у кольца) — те же деревья, номера после леса.
            int grove = 0;
            for (int p = 0; p < Plan.Pieces.Count; p++)
            {
                var piece = Plan.Pieces[p];
                if (piece.Shape != PieceShape.Tree) continue;
                MakeTree("Роща " + grove, Forest.Count + grove, piece.Center, piece.Size.Y / Forest.CrownTop, piece.Hits,
                    Harvestable.PlanBase + p);
                grove++;
            }
            // Отделка кусков плана (зубцы, крыши, окна, крепь шахт — WorldDetail):
            // как и деревья, строится при загрузке и в сцене не хранится — иначе
            // файл сцены вырос бы в пять раз.
            for (int p = 0; p < Plan.Pieces.Count; p++) WorldDetail.Decorate(Plan.Pieces[p], _holder);
            if (editing) Hide(_holder);
        }

        GameObject MakeTree(string name, int index, V3 foot, float scale, int hits, int key)
        {
            TreeKind kind;
            int variant;
            TreeShapes.Pick(index, out kind, out variant);
            var tree = new GameObject(name);
            tree.transform.SetParent(_holder, false);
            tree.transform.position = foot.ToUnity();
            // Поворот — из номера: одинаковые варианты не стоят строем.
            tree.transform.rotation = Quaternion.Euler(0f, index * 137.508f % 360f, 0f);
            tree.transform.localScale = Vector3.one * scale;
            tree.AddComponent<MeshFilter>().sharedMesh = TreeShapes.Get(kind, variant);
            tree.AddComponent<MeshRenderer>().sharedMaterials = new[]
            {
                Palette.Of("bark"),
                Palette.Of(kind == TreeKind.Spruce ? "needles" : "foliage"),
            };
            // Коллизия — ствол во весь рост и чуть шире (радиус 1.1, как у Godot-версии).
            var body = tree.AddComponent<CapsuleCollider>();
            body.radius = Forest.TrunkRadius;
            body.height = Forest.CrownTop;
            body.center = new Vector3(0f, Forest.CrownTop * 0.5f, 0f);
            // Номер — до AddComponent: OnEnable регистрирует источник по номеру.
            tree.SetActive(false);
            var harvest = tree.AddComponent<Harvestable>();
            harvest.Resource = ResourceKind.Wood;
            harvest.HitsLeft = hits;
            harvest.Key = key;
            tree.SetActive(true);
            return tree;
        }

        static void Hide(Transform root)
        {
            foreach (var t in root.GetComponentsInChildren<Transform>(true)) t.gameObject.hideFlags = HideFlags.DontSave;
        }

        /// Повалить дерево леса (по сети приходит номер).
        public void Fell(int index)
        {
            Forest.Fell(index);
            if (index < 0 || index >= Trees.Length || Trees[index] == null) return;
            Destroy(Trees[index]);
            Trees[index] = null;
        }

        /// Отпечаток плана: число частей и деревьев и суммы их мест и размеров.
        /// Сдвиг любой части плана меняет его.
        public static string Print(WorldPlan plan, Forest forest)
        {
            double sum = 0;
            foreach (var piece in plan.Pieces)
                sum += piece.Center.X * 1.3 + piece.Center.Y * 1.7 + piece.Center.Z * 1.9
                    + piece.Size.X + piece.Size.Y * 2.3 + piece.Size.Z * 2.9 + piece.Yaw * 3.1 + (int)piece.Shape;
            for (int i = 0; i < forest.Count; i++)
                sum += forest.Positions[i].X * 1.1 + forest.Positions[i].Z * 1.5 + forest.Scales[i];
            return plan.Pieces.Count + "|" + forest.Count + "|" + sum.ToString("0.00", CultureInfo.InvariantCulture);
        }
    }
}
