// «ДжваГода → Собрать мир»: неподвижный мир по плану ядра — в открытую сцену.
// Деревья сюда не входят: их сажает World при загрузке (TreeShapes).
//
// Карта одна на все партии (все семена плана — константы), поэтому её не
// строят при каждом запуске, а собирают здесь один раз: мир видно в
// редакторе, на места заглушек встанут ассеты, сетка навигации запечена.
// После правки плана в ядре — собрать заново: проверка WorldMatchesPlan и
// World при запуске скажут, если забыли. Без правки плана пункт ничего не
// трогает; «Собрать мир заново» — насильно (поменялся сам сборщик).
//
// Свои меши (рельеф, конус, валуны, вершины) и материалы заглушек ложатся
// файлами в Generated/: в файле сцены — только ссылки на них.
using System.Collections.Generic;
using System.IO;
using DjvaGoda.Core;
using DjvaGoda.Game;
using Unity.AI.Navigation;
using UnityEditor;
using UnityEditor.SceneManagement;
using UnityEngine;

namespace DjvaGoda.EditorTools
{
    public static class WorldBake
    {
        public const string GeneratedDir = "Assets/DjvaGoda/World/Generated";

        /// Собрать, только если план изменился: Unity раздаёт пересозданным
        /// объектам новые внутренние номера, и лишняя пересборка переписывает
        /// весь файл сцены.
        [MenuItem("ДжваГода/Собрать мир")]
        public static void BakeIfChanged()
        {
            var current = Object.FindAnyObjectByType<World>();
            if (current != null && current.PlanPrint == World.Print(current.Plan, current.Forest))
            {
                Debug.Log("Мир уже собран по текущему плану — сцена не тронута. Пересобрать насильно: ДжваГода → Собрать мир заново.");
                return;
            }
            Bake();
        }

        [MenuItem("ДжваГода/Собрать мир заново")]
        public static void Bake()
        {
            var scene = EditorSceneManager.GetActiveScene();
            foreach (var old in Object.FindObjectsByType<World>(FindObjectsInactive.Include))
                Object.DestroyImmediate(old.gameObject);
            if (!AssetDatabase.IsValidFolder(GeneratedDir))
            {
                Directory.CreateDirectory(GeneratedDir);
                AssetDatabase.Refresh();
            }
            AgentSettings();

            var root = new GameObject("Мир");
            var world = root.AddComponent<World>();
            Build(world);
            // Деревья в сцене не хранятся, но стволы должны попасть в сетку:
            // World посадил их без сохранения (OnEnable) — сетка их видит.
            world.Plant();
            root.AddComponent<NavWorld>();
            var surface = root.AddComponent<NavMeshSurface>();
            surface.collectObjects = CollectObjects.Children;
            surface.useGeometry = UnityEngine.AI.NavMeshCollectGeometry.PhysicsColliders;
            surface.BuildNavMesh();

            var kept = new HashSet<string>();
            SaveGeneratedAssets(root, kept);
            // Сетка — тоже на место прежней: ссылка из сцены не меняется.
            surface.enabled = false;
            surface.navMeshData = (UnityEngine.AI.NavMeshData)Store(surface.navMeshData, "NavMesh.asset", kept);
            surface.enabled = true;
            DropStale(kept);
            Sun();
            AssetDatabase.SaveAssets();
            EditorSceneManager.MarkSceneDirty(scene);
            EditorSceneManager.SaveScene(scene);
            Debug.Log("Мир собран: " + world.PlanPrint + ", деревьев леса " + world.Trees.Length);
        }

        /// Агент сетки — как в Godot-версии: радиус 0.5, рост 2, уклон 45°
        /// (под него считан рельеф), ступенька 0.5.
        static void AgentSettings()
        {
            var assets = AssetDatabase.LoadAllAssetsAtPath("ProjectSettings/NavMeshAreas.asset");
            if (assets.Length == 0) return;
            var settings = new SerializedObject(assets[0]);
            var agent = settings.FindProperty("m_Settings").GetArrayElementAtIndex(0);
            agent.FindPropertyRelative("agentRadius").floatValue = 0.5f;
            agent.FindPropertyRelative("agentHeight").floatValue = 2f;
            agent.FindPropertyRelative("agentSlope").floatValue = 45f;
            agent.FindPropertyRelative("agentClimb").floatValue = 0.5f;
            settings.ApplyModifiedProperties();
        }

        /// Свои меши и материалы — в файлы; встроенные (куб, цилиндр) уже ассеты.
        /// Файл с тем же именем перезаписывается НА МЕСТЕ: GUID не меняется, и
        /// пересборка без правки плана не трогает ни сцену, ни файлы.
        static void SaveGeneratedAssets(GameObject root, HashSet<string> kept)
        {
            var stored = new Dictionary<Object, Object>();
            // Посаженные деревья (DontSave) — не в файлы: их меши строятся при загрузке.
            foreach (var filter in root.GetComponentsInChildren<MeshFilter>(true))
                if (Kept(filter)) filter.sharedMesh = (Mesh)StoreOnce(filter.sharedMesh, ".asset", stored, kept);
            foreach (var hull in root.GetComponentsInChildren<MeshCollider>(true))
                if (Kept(hull)) hull.sharedMesh = (Mesh)StoreOnce(hull.sharedMesh, ".asset", stored, kept);
            foreach (var view in root.GetComponentsInChildren<MeshRenderer>(true))
                if (Kept(view)) view.sharedMaterial = (Material)StoreOnce(view.sharedMaterial, ".mat", stored, kept);
        }

        static bool Kept(Component c) { return (c.gameObject.hideFlags & HideFlags.DontSaveInEditor) == 0; }

        static Object StoreOnce(Object item, string extension, Dictionary<Object, Object> stored, HashSet<string> kept)
        {
            if (item == null) return null;
            Object asset;
            if (stored.TryGetValue(item, out asset)) return asset;
            string path = AssetDatabase.GetAssetPath(item);
            if (path.Length > 0 && !path.StartsWith(GeneratedDir))
                asset = item;
            else
                asset = Store(item, item.name + extension, kept);
            stored[item] = asset;
            return asset;
        }

        /// Положить в Generated/ под именем: есть файл — переписать его содержимое.
        static Object Store(Object item, string file, HashSet<string> kept)
        {
            string path = GeneratedDir + "/" + file;
            kept.Add(path);
            if (AssetDatabase.GetAssetPath(item) == path) return item;
            var existing = AssetDatabase.LoadAssetAtPath(path, item.GetType());
            if (existing == null)
            {
                AssetDatabase.CreateAsset(item, path);
                return item;
            }
            EditorUtility.CopySerialized(item, existing);
            existing.name = Path.GetFileNameWithoutExtension(file);
            EditorUtility.SetDirty(existing);
            return existing;
        }

        /// Файлы прежних сборок, которые эта не записала, — убрать.
        static void DropStale(HashSet<string> kept)
        {
            foreach (var guid in AssetDatabase.FindAssets("", new[] { GeneratedDir }))
            {
                string path = AssetDatabase.GUIDToAssetPath(guid);
                if (!kept.Contains(path)) AssetDatabase.DeleteAsset(path);
            }
            // Префаб дерева одной из прежних сборок: деревья теперь процедурные.
            if (AssetDatabase.IsValidFolder("Assets/DjvaGoda/World/Stubs")) AssetDatabase.DeleteAsset("Assets/DjvaGoda/World/Stubs");
        }

        static void Sun()
        {
            if (Object.FindAnyObjectByType<Light>() != null) return;
            var sun = new GameObject("Солнце").AddComponent<Light>();
            sun.type = LightType.Directional;
            sun.intensity = 1.1f;
            sun.shadows = LightShadows.Soft;
            sun.transform.rotation = Quaternion.Euler(50f, -30f, 0f);
        }

        // ---- Раскладка мира по плану (прежний WorldBuilder) ----

        static void Build(World world)
        {
            var relief = Relief.ForMap();
            var plan = WorldPlan.ForMap(relief);
            var forest = Forest.ForMap();
            var root = world.transform;
            BuildRelief(root, relief);
            var groups = new Dictionary<string, Transform>();
            foreach (var piece in plan.Pieces)
            {
                Transform parent;
                if (!groups.TryGetValue(piece.Group, out parent))
                {
                    parent = new GameObject(piece.Group).transform;
                    parent.SetParent(root, false);
                    groups[piece.Group] = parent;
                }
                Place(piece, parent);
            }
            world.PlanPrint = World.Print(plan, forest);
        }

        static void BuildRelief(Transform root, Relief relief)
        {
            var go = new GameObject("Рельеф");
            go.transform.SetParent(root, false);
            var mesh = Shapes.Relief(relief, MapLayout.WorldSize);
            go.AddComponent<MeshFilter>().sharedMesh = mesh;
            var view = go.AddComponent<MeshRenderer>();
            view.sharedMaterial = Palette.Of("ground");
            // Рельеф теней не отбрасывает: самозатенение пологого полотна — «акне».
            view.shadowCastingMode = UnityEngine.Rendering.ShadowCastingMode.Off;
            go.AddComponent<MeshCollider>().sharedMesh = mesh;
            go.isStatic = true;
        }

        static GameObject Place(Piece piece, Transform parent)
        {
            GameObject go;
            var at = piece.Center.ToUnity();
            var size = piece.Size.ToUnity();
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
                    go = MeshObject("Конус", Shapes.Cone(), at, new Vector3(size.x, size.y, size.x), 0f, false);
                    break;
                case PieceShape.Ramp:
                    go = Ramp(piece);
                    break;
                case PieceShape.Peak:
                    go = MeshObject("Вершина", Shapes.Peak(piece.ShapeSeed), at,
                        new Vector3(size.x * 0.5f, size.y, size.z * 0.5f), piece.Yaw, true);
                    break;
                case PieceShape.Rock:
                    go = MeshObject("Валун", Shapes.Rock(piece.ShapeSeed), at, size * 0.5f, piece.Yaw, true);
                    break;
                default:
                    // Дерево плана сажает World при загрузке (TreeShapes).
                    return null;
            }
            go.transform.SetParent(parent, true);
            var renderer = go.GetComponent<MeshRenderer>();
            if (renderer != null && piece.Shape != PieceShape.Tree) renderer.sharedMaterial = Palette.Of(piece.Material);
            if (piece.Decor)
            {
                var col = go.GetComponent<Collider>();
                if (col != null) Object.DestroyImmediate(col);
            }
            if (piece.Harvest.HasValue)
            {
                var harvest = go.GetComponent<Harvestable>();
                if (harvest == null) harvest = go.AddComponent<Harvestable>();
                harvest.Resource = piece.Harvest.Value;
                harvest.HitsLeft = piece.Hits;
            }
            SetStatic(go, !piece.Harvest.HasValue);
            return go;
        }

        static void SetStatic(GameObject go, bool value)
        {
            foreach (var t in go.GetComponentsInChildren<Transform>(true)) t.gameObject.isStatic = value;
        }

        /// У цилиндра Unity коллайдер — капсула: башня 9×20 м стала бы пилюлей
        /// со скруглёнными боками. Меняем на выпуклый меш самого цилиндра.
        static void SolidCylinder(GameObject go)
        {
            var capsule = go.GetComponent<CapsuleCollider>();
            if (capsule != null) Object.DestroyImmediate(capsule);
            var hull = go.AddComponent<MeshCollider>();
            hull.sharedMesh = go.GetComponent<MeshFilter>().sharedMesh;
            hull.convex = true;
        }

        static GameObject MeshObject(string name, Mesh mesh, Vector3 at, Vector3 scale, float yaw, bool solid)
        {
            var go = new GameObject(name);
            go.AddComponent<MeshFilter>().sharedMesh = mesh;
            go.AddComponent<MeshRenderer>();
            go.transform.SetPositionAndRotation(at, CoreSpace.YawToRotation(yaw));
            go.transform.localScale = scale;
            if (solid)
            {
                var hull = go.AddComponent<MeshCollider>();
                hull.sharedMesh = mesh;
                hull.convex = true;
            }
            return go;
        }

        /// Пандус на плато: наклонная плита с парапетами по бокам (без них с него падали).
        static GameObject Ramp(Piece piece)
        {
            float width = piece.Size.X, rise = piece.Size.Y, run = piece.Size.Z;
            float length = Mathf.Sqrt(run * run + rise * rise);
            float pitch = Mathf.Atan2(rise, run) * Mathf.Rad2Deg;
            var root = new GameObject("Пандус");
            // Подножие у фасада, подъём — к плато (к +z): плиту наклоняем −pitch,
            // и её дальний (+z) конец поднимается.
            var centre = (piece.Center + new V3(0f, rise * 0.5f, run * 0.5f)).ToUnity();
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
    }
}
