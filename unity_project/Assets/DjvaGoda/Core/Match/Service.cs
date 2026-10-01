// Служба стража у командира: приказы, засчитывание делом, повышение
// (перенос commander.gd — без тела командира и без поиска по миру).
//
// Мир сообщает события (убийство, разбитый обоз, секунды в точке), книжка
// стража продвигается по правилам. Всё считает хост.
using System;
using System.Collections.Generic;

namespace DjvaGoda.Core
{
    /// Служебная книжка одного стража.
    public class ServiceRecord
    {
        public OrderKind? Order;
        public int Progress;
        public int OrdersDone;
        /// После скольких сданных дают последний бой; растёт, если его провалить.
        public int FinalThreshold = Orders.OrdersForFinal;
        public bool IsLeader;
        float _holdSeconds;
        float _mineSeconds;
        float _escortSeconds;

        public bool Done { get { return Order.HasValue && Progress >= Orders.TargetOf(Order.Value); } }

        void Clear()
        {
            Order = null;
            Progress = 0;
            _holdSeconds = 0f;
            _mineSeconds = 0f;
            _escortSeconds = 0f;
        }

        /// Доклад командиру: выдать первый приказ или принять выполненный,
        /// заплатить и выдать следующий. Возвращает слова командира.
        /// finalAvailable — злодей ещё жив; possible — выполним ли приказ сейчас.
        public string Report(Wallet pay, bool villainAlive, System.Func<OrderKind, bool> possible)
        {
            if (!Order.HasValue) return IssueNext(villainAlive, possible);
            if (!Done)
                return "Приказ не выполнен: " + Orders.ProgressText(Order.Value, Progress);
            var reward = Orders.RewardOf(Order.Value);
            for (int i = 0; i < reward.Length; i++)
                if (reward[i] > 0) pay.Add(i, reward[i]);
            OrdersDone += 1;
            string doneName = Orders.NameOf(Order.Value);
            Clear();
            return "Приказ «" + doneName + "» выполнен. " + IssueNext(villainAlive, possible);
        }

        string IssueNext(bool villainAlive, System.Func<OrderKind, bool> possible)
        {
            OrderKind kind;
            if (OrdersDone >= FinalThreshold && villainAlive) kind = OrderKind.Final;
            else kind = RotationNext(possible);
            Clear();
            Order = kind;
            return "Новый приказ: " + Orders.NameOf(kind);
        }

        OrderKind RotationNext(System.Func<OrderKind, bool> possible)
        {
            int start = OrdersDone % Orders.Rotation.Length;
            for (int step = 0; step < Orders.Rotation.Length; step++)
            {
                var kind = Orders.Rotation[(start + step) % Orders.Rotation.Length];
                if (possible == null || possible(kind)) return kind;
            }
            return OrderKind.Hold;
        }

        /// Держать дворец: секунды — только в точке и пока дворец наш.
        public void TickHold(float delta, bool inPalace, bool palaceOurs)
        {
            if (Order != OrderKind.Hold || !inPalace || !palaceOurs) return;
            _holdSeconds += delta;
            Progress = (int)_holdSeconds;
        }

        /// Набег: дойти до форта, потом вернуться живым во дворец.
        public string TickRaid(bool atFort, bool atCommander)
        {
            if (Order != OrderKind.Raid) return null;
            if (Progress <= 0 && atFort)
            {
                Progress = 1;
                return "Форт злодея достигнут. Возвращайся во дворец.";
            }
            if (Progress == 1 && atCommander) Progress = 2;
            return null;
        }

        /// Шахта: секунды у поляны, пока рядом нет чужих.
        public void TickMine(float delta, bool atMine, int hostilesNear)
        {
            if (Order != OrderKind.Mine || !atMine || hostilesNear > 0) return;
            _mineSeconds += delta;
            Progress = (int)_mineSeconds;
        }

        /// Сопровождение: секунды рядом со своим обозом на обратном пути.
        public void TickEscort(float delta, bool nearHomewardCart)
        {
            if (Order == OrderKind.Escort && nearHomewardCart) _escortSeconds += delta;
        }

        public string OnCaravanHome()
        {
            if (Order != OrderKind.Escort || _escortSeconds < Orders.EscortSeconds) return null;
            Progress = Orders.TargetOf(OrderKind.Escort);
            return "Обоз доведён. Доложи командиру.";
        }

        /// Страж убил кого-то. Решающий удар — только за личное убийство злодея.
        public void OnKill(Faction victim, bool victimIsLeader, bool nearPalace, bool victimIsRobber)
        {
            if (!Order.HasValue || victim == Faction.Guard) return;
            switch (Order.Value)
            {
                case OrderKind.Slay:
                    if (victim == Faction.Villain) Progress += 1;
                    break;
                case OrderKind.Final:
                    if (victim == Faction.Villain && victimIsLeader) Progress = Orders.TargetOf(OrderKind.Final);
                    break;
                case OrderKind.Defend:
                    if (nearPalace) Progress += 1;
                    break;
                case OrderKind.Hunt:
                    if (victimIsRobber) Progress += 1;
                    break;
            }
        }

        public void OnCaravanDestroyed(Faction owner)
        {
            if (Order == OrderKind.Intercept && owner == Faction.Villain) Progress += 1;
        }

        public void OnBuildingDown(Faction side, BuildingKind kind)
        {
            if (Order == OrderKind.Field && side == Faction.Villain && kind == BuildingKind.Farm)
                Progress = Orders.TargetOf(OrderKind.Field);
        }

        /// Страж погиб. Проваленный последний бой снимается, порог растёт —
        /// заслужи снова. Обычные приказы смерть не отменяет.
        public string OnDeath()
        {
            if (Order != OrderKind.Final || Done) return null;
            FinalThreshold = OrdersDone + Orders.OrdersForFinal;
            Clear();
            return "Последний бой провален. Служи дальше и заслужи снова.";
        }

        /// Можно ли принять командование: пять сданных, жив, командира нет.
        public bool CanPromote(bool alive, bool commanderOnDuty, bool guardHasLeader)
        {
            if (!commanderOnDuty || !alive || IsLeader) return false;
            if (OrdersDone < Orders.OrdersForPromotion) return false;
            return !guardHasLeader;
        }

        public string Promote(bool alive, bool commanderOnDuty, bool guardHasLeader)
        {
            if (!CanPromote(alive, commanderOnDuty, guardHasLeader))
            {
                if (OrdersDone < Orders.OrdersForPromotion)
                    return "Командование заслуживают службой: сдано приказов " + OrdersDone + " из "
                        + Orders.OrdersForPromotion + ".";
                return "Командовать сейчас некому и незачем.";
            }
            IsLeader = true;
            return "Страж принял командование";
        }
    }

    /// Пост распорядителя стражи. Он убиваем, но не насовсем: через три минуты
    /// снова встаёт на пост — налёт с последствиями, а не выключенная сторона.
    /// Он же помнит грабителей обоза стражи — на них висит погоня.
    public class CommanderPost
    {
        public static readonly V3 Position = new V3(270f, 6f, 235f);
        public const float RespawnDelay = 180f;
        /// Двор, который он обороняет: за его пределы за целью не идёт.
        public const float Leash = 45f;
        public const int RobbersKept = 12;

        public bool OnDuty { get; private set; }
        float _respawnLeft;
        readonly List<int> _robbers = new List<int>();

        public CommanderPost() { OnDuty = true; }

        public float RespawnLeft { get { return OnDuty ? 0f : _respawnLeft; } }

        public void OnDied()
        {
            if (!OnDuty) return;
            OnDuty = false;
            _respawnLeft = RespawnDelay;
        }

        /// Такт хоста. true — распорядитель только что вернулся (объявить).
        public bool Tick(float delta)
        {
            if (OnDuty) return false;
            _respawnLeft -= delta;
            if (_respawnLeft > 0f) return false;
            OnDuty = true;
            return true;
        }

        /// Доложить можно только живому, стоя рядом (по горизонтали).
        public bool InRange(V3 point)
        {
            return OnDuty && Position.FlatDistance(point) <= Orders.TalkRange;
        }

        /// Обоз стражи ограблен: все враги в 30 м от места — грабители.
        public void OnCaravanLost(V3 point, IEnumerable<KeyValuePair<int, V3>> livingHostiles)
        {
            foreach (var hostile in livingHostiles)
            {
                if (hostile.Value.FlatDistance(point) > Orders.RobberRadius) continue;
                if (!_robbers.Contains(hostile.Key)) _robbers.Add(hostile.Key);
            }
            while (_robbers.Count > RobbersKept) _robbers.RemoveAt(0);
        }

        public bool IsRobber(int id) { return _robbers.Contains(id); }

        /// Погоню дают, только пока жив хоть один грабитель.
        public bool AnyRobberAlive(Func<int, bool> alive)
        {
            foreach (int id in _robbers)
                if (alive(id)) return true;
            return false;
        }
    }
}
