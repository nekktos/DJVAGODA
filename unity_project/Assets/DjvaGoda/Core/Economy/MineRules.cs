// Шахта: сколько копит и как от копателей (перенос mine.gd).
//
// Ответ автора от 30.09: «на шахтах тоже физически должны работать, но не
// обязательно таскать руками, приоритетнее загрузить обоз». Сама шахта даёт
// малую долю; каждый шахтёр у входа прибавляет свою; добытое копится в шахте
// и уезжает только обозом.
using System.Collections.Generic;

namespace DjvaGoda.Core
{
    public class MineState
    {
        public const int StockpileCap = 300;
        public const float PassiveShare = 0.2f;
        public const float DiggerShare = 0.4f;
        public const int MaxDiggers = 4;
        public const float DiggerMemory = 3f;

        /// Единиц в секунду при полной (1.0) доле — прежние скорости единой шахты.
        public static float BaseRate(ResourceKind kind)
        {
            switch (kind)
            {
                case ResourceKind.Iron: return 1.6f;
                case ResourceKind.Stone: return 3f;
                case ResourceKind.Coal: return 1.6f;
                case ResourceKind.Gold: return 0.6f;
                default: return 0f;
            }
        }

        public readonly ResourceKind Kind;
        public int[] Stored = Res.Empty();
        float _fraction;
        readonly Dictionary<int, float> _diggers = new Dictionary<int, float>();

        public MineState(ResourceKind kind)
        {
            Kind = kind;
        }

        /// Батрак ударил кайлом у входа.
        public void Dig(int workerId)
        {
            _diggers[workerId] = DiggerMemory;
        }

        public int Diggers { get { return _diggers.Count; } }

        public float Share
        {
            get { return PassiveShare + DiggerShare * System.Math.Min(_diggers.Count, MaxDiggers); }
        }

        /// Такт хоста: забыть ушедших копателей и докопать.
        public void Tick(float delta)
        {
            var gone = new List<int>();
            var keys = new List<int>(_diggers.Keys);
            foreach (var id in keys)
            {
                _diggers[id] -= delta;
                if (_diggers[id] <= 0f) gone.Add(id);
            }
            foreach (var id in gone) _diggers.Remove(id);

            _fraction += BaseRate(Kind) * Share * delta;
            int whole = (int)_fraction;
            if (whole <= 0) return;
            _fraction -= whole;
            int index = (int)Kind;
            Stored[index] = System.Math.Min(StockpileCap, Stored[index] + whole);
        }

        /// Забрать до limit единиц каждого ресурса; вернуть взятое.
        public int[] Take(int limit)
        {
            var taken = Res.Empty();
            for (int i = 0; i < Res.Count; i++)
            {
                int amount = System.Math.Min(limit, Stored[i]);
                Stored[i] -= amount;
                taken[i] = amount;
            }
            return taken;
        }
    }
}
