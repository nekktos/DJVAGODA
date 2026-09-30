// Сетка навигации мира (перенос navigation.gd) на встроенном API движка.
//
// Печётся по коллайдерам во время игры: мир процедурный, запечь заранее
// нечего. Перепечка — когда встала или снесена постройка: в Godot-версии
// сетку сначала пекли один раз, и ИИ упирался в новые дома. Перепечка
// асинхронная (UpdateNavMeshDataAsync), чтобы кадр не вставал — там это
// стоило 80-93 мс, пока не вынесли в поток.
//
// Путь отдаётся ядру точками (PathFinder): мозги ИИ — отряд, герой — сами
// решают, куда идти, и берут у сетки только дорогу.
using System.Collections.Generic;
using DjvaGoda.Core;
using UnityEngine;
using UnityEngine.AI;

namespace DjvaGoda.Game
{
    public class NavWorld : MonoBehaviour
    {
        /// Точка на сетке ищется не дальше этого по высоте: иначе с плато
        /// «ближайшей» оказывалась земля под ним (LEVEL_TOLERANCE Godot-версии).
        public const float LevelTolerance = 3f;
        public const float SampleRadius = 12f;

        NavMeshData _data;
        NavMeshDataInstance _instance;
        AsyncOperation _baking;
        bool _dirty;
        readonly List<NavMeshBuildSource> _sources = new List<NavMeshBuildSource>();
        Bounds _bounds;

        /// Сколько перепечек закончено — проверки ждут по нему.
        public int Bakes { get; private set; }
        public bool Ready { get { return Bakes > 0; } }

        public static NavMeshBuildSettings Settings()
        {
            var settings = NavMesh.GetSettingsByID(0);
            settings.agentRadius = 0.5f;
            settings.agentHeight = 2f;
            // Потолок уклона 45° — под него считан рельеф (Relief).
            settings.agentSlope = 45f;
            settings.agentClimb = 0.5f;
            return settings;
        }

        void Start()
        {
            _bounds = new Bounds(Vector3.zero, new Vector3(MapLayout.WorldSize + 20f, 200f, MapLayout.WorldSize + 20f));
            _data = new NavMeshData();
            _instance = NavMesh.AddNavMeshData(_data);
            // Первая выпечка — сразу и целиком: без сетки ИИ стоит.
            Collect();
            NavMeshBuilder.UpdateNavMeshData(_data, Settings(), _sources, _bounds);
            Bakes = 1;
        }

        void OnDestroy()
        {
            _instance.Remove();
        }

        void Collect()
        {
            _sources.Clear();
            var markups = new List<NavMeshBuildMarkup>();
            NavMeshBuilder.CollectSources(_bounds, ~0, NavMeshCollectGeometry.PhysicsColliders, 0, markups, _sources);
            // Персонажи и бойцы — не стены: их коллайдеры в сетку не пекутся,
            // иначе у каждого стоящего в сетке была бы дыра по его форме.
            _sources.RemoveAll(source => source.component is CharacterController);
        }

        /// Постройка встала или снесена — перепечь, когда закончится текущая выпечка.
        public void MarkDirty() { _dirty = true; }

        void Update()
        {
            if (_baking != null)
            {
                if (!_baking.isDone) return;
                _baking = null;
                Bakes++;
            }
            if (!_dirty) return;
            _dirty = false;
            Collect();
            _baking = NavMeshBuilder.UpdateNavMeshDataAsync(_data, Settings(), _sources, _bounds);
        }

        /// Ближайшая точка сетки на том же уровне: сперва — не дальше 3 м по
        /// высоте, иначе — любая ближайшая.
        public V3 ClosestPoint(V3 point)
        {
            var at = point.ToUnity();
            NavMeshHit hit;
            if (NavMesh.SamplePosition(at, out hit, SampleRadius, NavMesh.AllAreas) && Mathf.Abs(hit.position.y - at.y) <= LevelTolerance)
                return hit.position.ToCore();
            if (NavMesh.SamplePosition(at, out hit, SampleRadius * 4f, NavMesh.AllAreas))
                return hit.position.ToCore();
            return point;
        }

        /// Путь по сетке, точками ядра; пусто — пути нет.
        public List<V3> PathBetween(V3 from, V3 to)
        {
            var result = new List<V3>();
            var path = new NavMeshPath();
            if (!NavMesh.CalculatePath(ClosestPoint(from).ToUnity(), ClosestPoint(to).ToUnity(), NavMesh.AllAreas, path))
                return result;
            if (path.status == NavMeshPathStatus.PathInvalid) return result;
            foreach (var corner in path.corners) result.Add(corner.ToCore());
            return result;
        }

        /// Для мозгов ИИ ядра (WarbandBrain.Think и др.).
        public PathFinder Finder { get { return PathBetween; } }
    }
}
