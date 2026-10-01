// Рейс обоза: по нарисованному маршруту к шахте, погрузка, обратно тем же
// путём, выгрузка на склад (перенос caravan.gd).
//
// Здесь — ход по маршруту на плоскости, объезд построек, пропуск точки,
// оказавшейся внутри дома, упряжка, перехват и путь вперёд для погони.
// Высоту (посадка на землю), модель и звук держит Unity-слой.
using System;
using System.Collections.Generic;

namespace DjvaGoda.Core
{
    public enum TripEvent { None, Loaded, Arrived, StorageFull, Finished }

    public class CaravanTrip
    {
        /// Насколько сильно объезд построек перевешивает прямой курс.
        public const float AvoidWeight = 1.8f;
        public const float TurnRate = 1.6f;

        public Faction Side;
        public int Owner;
        public List<V3> Route;
        public CaravanState State = CaravanState.ToMine;
        public V3 Position;
        public float Yaw;
        public float Health = CaravanRules.MaxHealth;
        public int[] Cargo = Res.Empty();
        public int Horses;
        public float HorsePool;
        /// Стоит: лошадей нет или рядом враг.
        public bool Halted;
        /// Стоит у полного склада и ждёт места.
        public bool Waiting;
        int _leg;
        float _timer;
        int _slideSide;

        public CaravanTrip(Faction side, int owner, List<V3> route, int horses)
        {
            Side = side;
            Owner = owner;
            Route = new List<V3>(route);
            Horses = Res.Clamp(horses, CaravanRules.HorsesMin, CaravanRules.HorsesMax);
            HorsePool = CaravanRules.HorseHealth * Horses;
            Position = Route.Count > 0 ? Route[0] : new V3(0f, 0f, 0f);
        }

        public float SpeedNow { get { return CaravanRules.SpeedFor(Horses); } }

        public int CargoTotal
        {
            get
            {
                int total = 0;
                foreach (int value in Cargo) total += value;
                return total;
            }
        }

        /// Такт хоста. enemyNear — враг в 18 м; load — что даст шахта у конца
        /// маршрута (null — шахты рядом нет); wallet — казна стороны.
        public TripEvent Tick(float delta, bool enemyNear, IList<KeyValuePair<BuildingKind, V3>> buildings,
            Func<V3, int[]> load, Wallet wallet)
        {
            Halted = Horses <= 0 || enemyNear;
            switch (State)
            {
                case CaravanState.ToMine:
                    if (Advance(delta, false, buildings))
                    {
                        State = CaravanState.Loading;
                        _timer = CaravanRules.LoadSeconds;
                    }
                    return TripEvent.None;
                case CaravanState.Loading:
                    _timer -= delta;
                    if (_timer > 0f) return TripEvent.None;
                    var taken = load != null ? load(Position) : null;
                    if (taken != null) Cargo = Res.Fit(taken);
                    State = CaravanState.ToHome;
                    return TripEvent.Loaded;
                case CaravanState.ToHome:
                    if (Advance(delta, true, buildings))
                    {
                        State = CaravanState.Unloading;
                        _timer = CaravanRules.LoadSeconds;
                        return TripEvent.Arrived;
                    }
                    return TripEvent.None;
                case CaravanState.Unloading:
                    _timer -= delta;
                    if (_timer > 0f) return TripEvent.None;
                    if (wallet == null || CaravanRules.Unload(Cargo, wallet))
                    {
                        Waiting = false;
                        State = CaravanState.Finished;
                        return TripEvent.Finished;
                    }
                    _timer = CaravanRules.WaitRetry;
                    if (Waiting) return TripEvent.None;
                    // Оповестить сторону один раз: «Склад полон, построй ещё склад».
                    Waiting = true;
                    return TripEvent.StorageFull;
                default:
                    return TripEvent.None;
            }
        }

        /// Проехать по маршруту. true — маршрут пройден до конца.
        /// Обратный путь — те же точки в обратном порядке.
        bool Advance(float delta, bool backwards, IList<KeyValuePair<BuildingKind, V3>> buildings)
        {
            if (Route.Count < 2) return true;
            if (Halted) return false;
            int index = Res.Clamp(backwards ? Route.Count - 1 - _leg : _leg, 0, Route.Count - 1);
            var target = Route[index];
            // Точку, оказавшуюся внутри дома, пропускаем: объезд к ней не пустит.
            // Концы (склад и шахта) — никогда: к ним и едут.
            if (index != 0 && index != Route.Count - 1 && BlockedPoint(target, buildings)) return NextLeg();
            var toTarget = (target - Position).Flat();
            if (toTarget.Length() <= CaravanRules.WaypointReach) return NextLeg();
            var dir = AvoidBuildings(toTarget.Normalized(), buildings);
            Position = Position + dir * (SpeedNow * delta);
            Yaw = RotateToward(Yaw, (float)Math.Atan2(dir.X, dir.Z), TurnRate * delta);
            return false;
        }

        bool NextLeg()
        {
            _slideSide = 0;
            _leg++;
            if (_leg < Route.Count) return false;
            _leg = 0;
            return true;
        }

        /// Отвернуть от стены: толчок от ближайшей точки коробки дома разворачивает
        /// обоз вдоль стены, а не останавливает его. Постройки стоят по осям.
        public V3 AvoidBuildings(V3 dir, IList<KeyValuePair<BuildingKind, V3>> buildings)
        {
            var push = new V3(0f, 0f, 0f);
            if (buildings != null)
                foreach (var building in buildings)
                {
                    if (Res.Walkable(building.Key)) continue;
                    var size = Res.BuildingSize(building.Key);
                    float hx = size.X * 0.5f, hz = size.Z * 0.5f;
                    if (IsTerminal(building.Value, hx, hz)) continue;
                    float lx = Position.X - building.Value.X;
                    float lz = Position.Z - building.Value.Z;
                    var away = new V3(lx - Clamp(lx, -hx, hx), 0f, lz - Clamp(lz, -hz, hz));
                    float dist = away.Length();
                    if (dist > CaravanRules.BuildingClearance) continue;
                    if (dist < 0.05f)
                    {
                        away = new V3(lx, 0f, lz);
                        if (away.Length() < 0.05f) away = new V3(1f, 0f, 0f);
                        dist = 0.05f;
                    }
                    push = push + away.Normalized() * ((CaravanRules.BuildingClearance - dist) / CaravanRules.BuildingClearance);
                }
            if (push.Length() < 0.001f) return dir;
            var outward = push.Normalized();
            var steered = (dir + outward * AvoidWeight).Flat();
            // В ЛОБ НА СТЕНУ толчок ровно против курса, и сумма тянет назад:
            // обоз качался у стены до конца партии (проверка ядра «дом на линии
            // маршрута»). В Godot-версии маршрут почти всегда огибал дом по
            // навигации, и это не всплывало. Тогда — вдоль стены, в сторону цели.
            // Сторону обхода ЗАПОМИНАЕМ до следующей точки маршрута: выбранная
            // заново, она перещёлкивалась у середины стены и на краю зоны
            // толчка, и обоз метался влево-вправо.
            if (steered.X * dir.X + steered.Z * dir.Z <= 0.1f)
            {
                var along = new V3(-outward.Z, 0f, outward.X);
                if (_slideSide == 0) _slideSide = along.X * dir.X + along.Z * dir.Z < 0f ? -1 : 1;
                steered = along * _slideSide + outward * 0.3f;
            }
            return steered.Length() > 0.01f ? steered.Normalized() : dir;
        }

        bool BlockedPoint(V3 point, IList<KeyValuePair<BuildingKind, V3>> buildings)
        {
            if (buildings == null) return false;
            foreach (var building in buildings)
            {
                if (Res.Walkable(building.Key)) continue;
                var size = Res.BuildingSize(building.Key);
                float hx = size.X * 0.5f, hz = size.Z * 0.5f;
                if (IsTerminal(building.Value, hx, hz)) continue;
                if (BoxGap(point, building.Value, hx, hz) < CaravanRules.BuildingClearance * 0.5f) return true;
            }
            return false;
        }

        /// Постройка на конце маршрута (склад, у которого разгружаются) — не помеха.
        bool IsTerminal(V3 at, float hx, float hz)
        {
            if (Route.Count < 2) return false;
            return BoxGap(Route[0], at, hx, hz) < 1f || BoxGap(Route[Route.Count - 1], at, hx, hz) < 1f;
        }

        public static float BoxGap(V3 at, V3 box, float hx, float hz)
        {
            float dx = Math.Max(Math.Abs(at.X - box.X) - hx, 0f);
            float dz = Math.Max(Math.Abs(at.Z - box.Z) - hz, 0f);
            return (float)Math.Sqrt(dx * dx + dz * dz);
        }

        static float Clamp(float v, float lo, float hi) { return v < lo ? lo : (v > hi ? hi : v); }

        static float RotateToward(float from, float to, float step)
        {
            float diff = to - from;
            while (diff > Math.PI) diff -= (float)(2 * Math.PI);
            while (diff < -Math.PI) diff += (float)(2 * Math.PI);
            if (Math.Abs(diff) <= step) return to;
            return from + Math.Sign(diff) * step;
        }

        /// Путь, который обозу ещё предстоит: по нему считают перехват.
        public List<V3> PathAhead()
        {
            var ahead = new List<V3>();
            int last = Route.Count - 1;
            if (Route.Count < 2) return ahead;
            switch (State)
            {
                case CaravanState.ToMine:
                    for (int i = Res.Clamp(_leg, 0, last); i <= last; i++) ahead.Add(Route[i]);
                    for (int i = last - 1; i >= 0; i--) ahead.Add(Route[i]);
                    break;
                case CaravanState.Loading:
                    for (int i = last; i >= 0; i--) ahead.Add(Route[i]);
                    break;
                case CaravanState.ToHome:
                    for (int i = Res.Clamp(last - _leg, 0, last); i >= 0; i--) ahead.Add(Route[i]);
                    break;
            }
            return ahead;
        }

        /// Удар по упряжке: лошади гибнут по одной, когда общий запас здоровья
        /// падает ниже их числа. Без лошадей обоз встаёт.
        public void HurtHarness(float amount)
        {
            if (Horses <= 0) return;
            HorsePool = Math.Max(0f, HorsePool - amount);
            int left = (int)Math.Ceiling(HorsePool / CaravanRules.HorseHealth);
            if (left < Horses) Horses = Math.Max(0, left);
            if (Horses <= 0) Halted = true;
        }

        /// Увести лошадей у стоящего обоза. Возвращает, сколько уведено.
        public int CaptureHorses()
        {
            if (Horses <= 0 || !Halted) return 0;
            int taken = Horses;
            Horses = 0;
            HorsePool = 0f;
            Halted = true;
            return taken;
        }

        /// Перехват: обоз едет на склад перехватчика пройденным им путём.
        public void Redirect(Faction side, int owner, List<V3> walked)
        {
            if (walked == null || walked.Count < 2) return;
            Side = side;
            Owner = owner;
            Route = new List<V3>(walked);
            _leg = 0;
            State = CaravanState.ToHome;
            Halted = false;
        }
    }
}
