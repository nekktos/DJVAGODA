// Куда шагнуть к цели: напрямую или по сетке (перенос unit.gd::_next_step,
// _note_blocked). Общий для бойцов, батраков и героя ИИ.
//
// Ближе 25 м и не упёрся — напрямую. Дальше — путь по сетке, перезапрос, если
// цель сдвинулась на 6 м; точка пути пройдена за 2.5 м. Путь, который
// кончается дальше от цели, чем мы стоим, только уводит (цель на круче без
// сетки) — тогда напрямую, и пока цель не сдвинулась, сетку не спрашиваем.
// «Упёрся» меряется ПРОДВИЖЕНИЕМ (сокращается ли расстояние), а не касанием:
// вдоль скалы боец скользит с полной скоростью и цель не приближает.
using System.Collections.Generic;

namespace DjvaGoda.CoreOld
{
    public class PathFollower
    {
        List<V3> _path = new List<V3>();
        int _index;
        V3? _pathGoal;
        V3? _directGoal;
        float _blocked;
        V3? _bestGoal;
        float _bestGap = float.MaxValue;

        public float Blocked { get { return _blocked; } }
        public bool OnPath { get { return _path.Count > 0 && _index < _path.Count; } }

        /// Следующая точка, к которой идти. path — сетка (может быть null: сетки ещё нет).
        public V3 NextStep(V3 here, V3 goal, PathFinder path, System.Func<V3, V3> closest)
        {
            if (here.Distance(goal) <= UnitStats.DirectRange && _blocked < UnitStats.BlockedSeconds)
            {
                _path.Clear();
                _pathGoal = null;
                return goal;
            }
            if (path == null) return goal;
            if (_directGoal.HasValue && _directGoal.Value.Distance(goal) <= UnitStats.RepathDistance) return goal;
            _directGoal = null;

            if (_path.Count == 0 || _index >= _path.Count || !_pathGoal.HasValue
                || _pathGoal.Value.Distance(goal) > UnitStats.RepathDistance)
            {
                var found = path(here, closest != null ? closest(goal) : goal);
                _path = found ?? new List<V3>();
                _index = 0;
                _pathGoal = goal;
                if (_path.Count > 0)
                {
                    var end = _path[_path.Count - 1];
                    if (end.FlatDistance(goal) > here.FlatDistance(goal) + 1f)
                    {
                        _path.Clear();
                        _directGoal = goal;
                        return goal;
                    }
                }
            }
            while (_index < _path.Count)
            {
                var point = _path[_index];
                if (point.FlatDistance(here) > UnitStats.WaypointRadius) return point;
                _index++;
            }
            return goal;
        }

        /// Такт после движения: копит «упёрся», пока расстояние до цели не
        /// сокращается на 0.6 м; отпускает вдвое быстрее, чем копит.
        public void NoteProgress(float delta, bool moving, V3 here, V3? goal)
        {
            if (!moving)
            {
                _blocked = System.Math.Max(0f, _blocked - delta * 2f);
                return;
            }
            if (!goal.HasValue) return;
            if (!_bestGoal.HasValue || _bestGoal.Value.Distance(goal.Value) > UnitStats.RepathDistance)
            {
                _bestGoal = goal;
                _bestGap = float.MaxValue;
            }
            float gap = here.FlatDistance(goal.Value);
            if (gap < _bestGap - UnitStats.ProgressStep)
            {
                _bestGap = gap;
                _blocked = System.Math.Max(0f, _blocked - delta * 2f);
            }
            else
            {
                _blocked += delta;
            }
        }
    }
}
