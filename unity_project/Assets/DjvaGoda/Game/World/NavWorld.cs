// Сетка навигации мира (перенос navigation.gd) на AI Navigation.
//
// Сетка запечена в редакторе вместе с миром (NavMeshSurface на корне «Мир»,
// «ДжваГода → Собрать мир»). Постройки, вставшие во время игры, вырезают
// себя из неё сами (NavMeshObstacle с вырезанием в BuildingActor): в
// Godot-версии сетку сперва пекли один раз, и ИИ упирался в новые дома, а
// полная перепечка стоила 80-93 мс.
//
// Путь отдаётся ядру точками (PathFinder): мозги ИИ — отряд, герой — сами
// решают, куда идти, и берут у сетки только дорогу.
using System.Collections.Generic;
using DjvaGoda.Core;
using Unity.AI.Navigation;
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

        /// Сетка запечена и подключена.
        public bool Ready
        {
            get
            {
                var surface = GetComponent<NavMeshSurface>();
                return surface != null && surface.navMeshData != null && surface.isActiveAndEnabled;
            }
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
