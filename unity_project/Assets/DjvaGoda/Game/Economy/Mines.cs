// Шахты карты (перенос economy/mine.gd и world.gd: mine_near, mine_dock) —
// у хоста. Шахта копит сама малую долю, каждый шахтёр у входа прибавляет свою
// (MineState ядра); добытое уезжает только обозом: обоз в конце маршрута
// берёт у той шахты, к входу которой приехал.
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
            for (int i = 0; i < _worked.Length; i++) _worked[i] = -1;
        }

        /// Шахта, куда сторона последний раз отправила обоз: туда и идут её
        /// шахтёры. Иначе копали ближнюю (у злодея — железо), а обоз за золотом
        /// привозил из дальней шахты по десятку (долгая партия на новой карте).
        static readonly int[] _worked = { -1, -1, -1 };

        public static void Worked(int side, int index)
        {
            if (side >= 0 && side < _worked.Length && index >= 0 && index < MapLayout.Mines.Length) _worked[side] = index;
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
