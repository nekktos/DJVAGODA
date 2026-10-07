// Шахты карты (перенос economy/mine.gd и world.gd: mine_near, mine_dock) —
// у хоста. Шахта копит сама малую долю, каждый шахтёр у входа прибавляет свою
// (MineState ядра); добытое уезжает только обозом: обоз в конце маршрута
// берёт у той шахты, к входу которой приехал.
using System.Collections.Generic;
using DjvaGoda.Core;

namespace DjvaGoda.Game
{
    public static class Mines
    {
        static MineState[] _states;

        /// Номер места работы шахты для мозга батрака: отрицательный, чтобы не
        /// пересечься с номерами участников мира.
        public const int SiteBase = -100;

        public static MineState[] States
        {
            get
            {
                if (_states == null) Reset();
                return _states;
            }
        }

        public static void Reset()
        {
            _states = new MineState[MapLayout.Mines.Length];
            for (int i = 0; i < _states.Length; i++) _states[i] = new MineState(MapLayout.Mines[i].Kind);
            for (int i = 0; i < _worked.Length; i++)
            {
                _worked[i] = -1;
                _visited[i].Clear();
            }
        }

        /// Шахтёры стороны сидят на самой медленной руде (золото) из шахт, куда
        /// она уже возила обоз: быстрые копятся и сами. Раньше копали ближнюю
        /// (у злодея — железо) или бегали через карту за каждым новым обозом,
        /// и злодей-ИИ сидел без золота на бойцов (долгие партии на новой карте).
        static readonly int[] _worked = { -1, -1, -1 };
        static readonly HashSet<int>[] _visited = { new HashSet<int>(), new HashSet<int>(), new HashSet<int>() };

        public static void Worked(int side, int index)
        {
            if (side < 0 || side >= _worked.Length || index < 0 || index >= MapLayout.Mines.Length) return;
            _visited[side].Add(index);
            int best = _worked[side];
            foreach (int mine in _visited[side])
                if (best < 0 || MineState.BaseRate(MapLayout.Mines[mine].Kind) < MineState.BaseRate(MapLayout.Mines[best].Kind))
                    best = mine;
            _worked[side] = best;
        }

        public static void Tick(float delta)
        {
            foreach (var mine in States) mine.Tick(delta);
        }

        public static V3 Dock(int index) { return MapLayout.MineEntrance(MapLayout.Mines[index].At); }

        /// Шахта, чей вход ближе всего к точке.
        public static int Nearest(V3 point)
        {
            int best = 0;
            float bestDistance = float.MaxValue;
            for (int i = 0; i < MapLayout.Mines.Length; i++)
            {
                float d = Dock(i).FlatDistance(point);
                if (d < bestDistance)
                {
                    bestDistance = d;
                    best = i;
                }
            }
            return best;
        }

        /// Погрузка обоза у входа: до вместимости обоза; не у шахты — ничего.
        public static int[] Load(V3 at)
        {
            int index = Nearest(at);
            if (Dock(index).FlatDistance(at) > CaravanRules.LoadReach) return null;
            return States[index].Take(CaravanRules.Capacity);
        }

        /// Место работы шахтёра: куда ходит обоз стороны, а пока не ходил —
        /// шахта, ближайшая к дому.
        public static WorkSite SiteFor(V3 home, int side)
        {
            int index = side >= 0 && side < _worked.Length && _worked[side] >= 0 ? _worked[side] : Nearest(home);
            var mine = MapLayout.Mines[index];
            return new WorkSite
            {
                Id = SiteBase - index,
                Kind = SiteKind.Mine,
                At = mine.At,
                Dock = Dock(index),
                Resource = mine.Kind,
                Body = MapLayout.MineRock * 0.5f,
            };
        }

        /// Шахтёр ударил кайлом у входа.
        public static void Dig(int siteId, int workerId)
        {
            int index = SiteBase - siteId;
            if (index >= 0 && index < States.Length) States[index].Dig(workerId);
        }
    }
}
