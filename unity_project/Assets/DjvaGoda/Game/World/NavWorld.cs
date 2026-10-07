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
        ///
        /// Длинный путь (поселение эльфов — дворец) у CalculatePath упирается в
        /// предел узлов поиска и приходит ЧАСТИЧНЫМ, хотя каждый его отрезок
        /// проходим: поймано проверкой «до каждой метки обучения можно дойти».
        /// Поэтому частичный путь досчитывается от своего конца, кусками.
        public const int MaxStitches = 6;

        public List<V3> PathBetween(V3 from, V3 to)
        {
            var path = Stitched(from, to);
            bool reached = path.Count > 0 && path[path.Count - 1].FlatDistance(ClosestPoint(to)) < 2f;
            if (reached) return path;
            // Поиск упёрся в борт плато или в кольцо гор (предел узлов), а вход
            // туда один: на плато — пандус, к форту — перевал. Идём через вход.
            var gate = GateBetween(from, to);
            if (!gate.HasValue) return path;
            var first = Stitched(from, gate.Value);
            var second = Stitched(gate.Value, to);
            if (first.Count == 0 || second.Count == 0) return path;
            for (int i = 1; i < second.Count; i++) first.Add(second[i]);
            return first;
        }

        /// Вход, через который лежит путь: пандус замка или перевал злодея.
        static V3? GateBetween(V3 from, V3 to)
        {
            bool fromUp = MapLayout.OnPlateau(from.X, from.Z, 0f), toUp = MapLayout.OnPlateau(to.X, to.Z, 0f);
            if (fromUp != toUp) return MapLayout.RampFoot;
            bool fromRing = MapLayout.InVillainRing(from.X, from.Z, 0f), toRing = MapLayout.InVillainRing(to.X, to.Z, 0f);
            if (fromRing != toRing) return MapLayout.VillainPass;
            return null;
        }

        List<V3> Stitched(V3 from, V3 to)
        {
            var result = new List<V3>();
            var start = ClosestPoint(from).ToUnity();
            var goal = ClosestPoint(to).ToUnity();
            var path = new NavMeshPath();
            for (int piece = 0; piece <= MaxStitches; piece++)
            {
                if (!NavMesh.CalculatePath(start, goal, NavMesh.AllAreas, path) || path.status == NavMeshPathStatus.PathInvalid)
                    break;
                var corners = path.corners;
                // Стык: первая точка куска — конец предыдущего.
                for (int i = result.Count > 0 ? 1 : 0; i < corners.Length; i++) result.Add(corners[i].ToCore());
                if (path.status == NavMeshPathStatus.PathComplete || corners.Length == 0) break;
                var end = corners[corners.Length - 1];
                // Ни на шаг не продвинулись — дальше и правда не пройти.
                if ((end - start).sqrMagnitude < 1f) break;
                start = end;
            }
            return result;
        }

        /// Для мозгов ИИ ядра (WarbandBrain.Think и др.).
        public PathFinder Finder { get { return PathBetween; } }
    }
}
