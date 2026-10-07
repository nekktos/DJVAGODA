// Военный отряд стороны под ИИ (перенос ai/warband.gd).
//
// Отряд выходит с базы, идёт колонной к цели, дерётся с тем, что встретил, и
// возвращается, когда его проредили. Не строит и не нанимает — состав держит
// гарнизон. Своего кода движения у отряда нет: бойцы получают то же, что от
// живого командира, — якорь строя, разворот и вид построения. Почему числа
// именно такие (радиус набега 800, точка маршрута 5 м по ближайшему бойцу,
// якорь в 14 м впереди…) — в комментариях Godot-версии.
//
// Мозг чистый: мир он видит через WarbandView, путь берёт у PathFinder.
// Считает только хост.
using System;
using System.Collections.Generic;

namespace DjvaGoda.Core
{
    public enum WarbandState { Hold, March, Fight, Return }

    /// Точка со стороной: живой игрок, боец или постройка.
    public struct SidedPoint
    {
        public readonly V3 At;
        public readonly int Side;

        public SidedPoint(V3 at, int side)
        {
            At = at;
            Side = side;
        }
    }

    public class CartSighting
    {
        public int Id;
        public V3 At;
        public int Side;
        public float Speed = CaravanRules.Speed;
        /// Оставшийся путь обоза — по нему считается точка перехвата.
        public List<V3> Ahead = new List<V3>();
    }

    /// Что отряд видит в момент раздумья. Собирает Unity-слой.
    public class WarbandView
    {
        /// Бойцы отряда (ополчение без хозяина, не вожак, не в охране обоза).
        public List<V3> Band = new List<V3>();
        /// Своё хозяйство: постройки и батраки стороны.
        public List<V3> Posts = new List<V3>();
        /// Живые игроки и бойцы всех сторон; враждебность отряд решает сам.
        public List<SidedPoint> Fighters = new List<SidedPoint>();
        public List<SidedPoint> Buildings = new List<SidedPoint>();
        public List<CartSighting> Carts = new List<CartSighting>();
        public bool HumanOnSide;
        public bool HasBarracks;
        /// Дворец, который этой стороне есть смысл брать (злодей, дворец не его);
        /// пусто — штурма нет.
        public V3? Palace;
        public int SidesLeft = Factions.Count;
    }

    /// Что отряд велит бойцам — ровно то, что велел бы живой командир.
    public struct WarbandOrder
    {
        public V3 Anchor;
        public float Yaw;
        public FormationKind Formation;
        public float Leash;
    }

    public delegate List<V3> PathFinder(V3 from, V3 to);

    public class WarbandBrain
    {
        public readonly Faction Side;
        public WarbandState State { get; private set; }
        public bool Defending { get; private set; }
        public V3? Goal { get; private set; }
        public V3? Anchor { get; private set; }
        public List<V3> Route = new List<V3>();
        /// Цель набега, объявленная в этом раздумье (для журнала), иначе null.
        public V3? Announced { get; private set; }

        float _stuckT;
        V3? _lastCentre;
        int _cartId = -1;
        float _thinkT;

        public WarbandBrain(Faction side) { Side = side; }

        V3 Base { get { return Factions.Spawn[(int)Side]; } }

        public string StateName
        {
            get { return Defending ? "защищает хозяйство" : AiStats.WarbandStateNames[(int)State]; }
        }

        public bool AtHome { get { return State == WarbandState.Hold; } }

        /// Такт хоста: каждый кадр двигает якорь, раз в две секунды думает.
        public WarbandOrder? Tick(float delta, WarbandView view, PathFinder path)
        {
            var order = Steer(view.Band);
            _thinkT += delta;
            if (_thinkT >= AiStats.WarbandThink)
            {
                _thinkT = 0f;
                Think(view, path);
            }
            return order;
        }

        /// Перенести якорь вдоль маршрута и отдать бойцам приказ.
        public WarbandOrder? Steer(List<V3> band)
        {
            if (!Anchor.HasValue) return null;
            var centre = BandPoint(band);
            while (Route.Count > 0 && Passed(band, centre, Route[0])) Route.RemoveAt(0);
            var here = LeadAlong(centre, Route, Goal ?? Anchor.Value);
            var course = Course(centre, Route);
            Anchor = here;
            float yaw = 0f;
            if (course.Length() > 0.5f) yaw = (float)Math.Atan2(course.X, course.Z);
            return new WarbandOrder
            {
                Anchor = here,
                Yaw = yaw,
                Formation = FormationFor(State),
                Leash = State == WarbandState.Hold ? AiStats.GarrisonLeash : AiStats.MarchLeash,
            };
        }

        public static FormationKind FormationFor(WarbandState state)
        {
            switch (state)
            {
                case WarbandState.March:
                case WarbandState.Return:
                    return FormationKind.Column;
                case WarbandState.Fight:
                    return FormationKind.Line;
                default:
                    return FormationKind.ShieldWall;
            }
        }

        public void Think(WarbandView view, PathFinder path)
        {
            Announced = null;
            var band = view.Band;
            if (band.Count == 0)
            {
                State = WarbandState.Hold;
                Defending = false;
                Goal = null;
                Anchor = null;
                Route.Clear();
                _stuckT = 0f;
                _lastCentre = null;
                return;
            }
            if (!Anchor.HasValue)
            {
                Anchor = Base;
                Goal = Base;
                State = WarbandState.Hold;
            }
            var was = State;
            var here = Anchor.Value;

            if (EnemyNear(view, here))
            {
                SetState(WarbandState.Fight, band);
                Goal = here;
                return;
            }

            // Своё хозяйство под ударом — идти защищать, если не в набеге.
            var threat = HomeThreat(view);
            bool raiding = was == WarbandState.March && !Defending;
            if (threat.HasValue && !raiding)
            {
                if (!Goal.HasValue || Goal.Value.Distance(threat.Value) > AiStats.ArriveRadius)
                    SetRoute(band, threat.Value, path);
                Defending = true;
                SetState(WarbandState.March, band);
                return;
            }
            Defending = false;

            switch (was)
            {
                case WarbandState.Fight:
                    if (Spent(band)) GoHome(band, path);
                    else PlanNext(view, path);
                    break;
                case WarbandState.March:
                    if (Spent(band) || IsStuck(band)) GoHome(band, path);
                    else if (Arrived(band, here)) PlanNext(view, path);
                    else Chase(view, path);
                    break;
                case WarbandState.Return:
                    if (here.Distance(Base) <= AiStats.ArriveRadius || IsStuck(band))
                    {
                        SetState(WarbandState.Hold, band);
                        Route.Clear();
                        Goal = Base;
                    }
                    else if (!Spent(band))
                    {
                        PlanNext(view, path);
                    }
                    break;
                default:
                    PlanNext(view, path);
                    break;
            }
        }

        void PlanNext(WarbandView view, PathFinder path)
        {
            var band = view.Band;
            if (band.Count < AiStats.GarrisonSize * AiStats.SallyFraction || StillSettling(view))
            {
                StandDown(band, path);
                return;
            }
            var target = PickTarget(view);
            if (!target.HasValue)
            {
                StandDown(band, path);
                return;
            }
            bool sameGoal = Goal.HasValue && Goal.Value.Distance(target.Value) <= AiStats.ArriveRadius;
            bool fresh = State != WarbandState.March || !sameGoal;
            SetState(WarbandState.March, band);
            SetRoute(band, target.Value, path);
            if (fresh) Announced = target;
        }

        /// Строящаяся сторона без живых игроков не уходит в набег, пока нет казармы:
        /// гарнизон — её единственная оборона.
        public bool StillSettling(WarbandView view)
        {
            if (!Factions.CanBuild(Side) || view.HumanOnSide) return false;
            return !view.HasBarracks;
        }

        void Chase(WarbandView view, PathFinder path)
        {
            var cart = CartById(view, _cartId);
            if (cart == null)
            {
                _cartId = -1;
                return;
            }
            var target = Intercept(view.Band, cart);
            if (Goal.HasValue && Goal.Value.Distance(target) <= AiStats.ArriveRadius) return;
            float stuck = _stuckT;
            SetRoute(view.Band, target, path);
            _stuckT = stuck;
        }

        /// Ближайшая враждебная постройка в радиусе набега, иначе ближайший обоз.
        /// Чужие точки появления целями не бывают по построению.
        public V3? PickTarget(WarbandView view)
        {
            // Войско в силе — на штурм дворца: цель злодея — дворец, а не одни
            // постройки стражи (playtest-10: «набеги не забегают в замок»).
            if (view.Palace.HasValue && view.Band.Count >= AiStats.AssaultBand) return view.Palace;
            var home = Base;
            var here = Anchor ?? home;
            V3? best = null;
            float bestDistance = float.MaxValue;
            foreach (var building in view.Buildings)
            {
                if (!Factions.Hostile((int)Side, building.Side)) continue;
                if (!ElvesFairGame(building.Side, view.SidesLeft)) continue;
                if (home.Distance(building.At) > AiStats.RaidRange) continue;
                float d = here.Distance(building.At);
                if (d < bestDistance)
                {
                    bestDistance = d;
                    best = building.At;
                }
            }
            if (best.HasValue) return best;

            CartSighting chosen = null;
            foreach (var cart in view.Carts)
            {
                if (!Factions.Hostile((int)Side, cart.Side)) continue;
                if (home.Distance(cart.At) > AiStats.RaidRange) continue;
                float d = here.Distance(cart.At);
                if (d < bestDistance)
                {
                    bestDistance = d;
                    chosen = cart;
                }
            }
            if (chosen == null)
            {
                _cartId = -1;
                return null;
            }
            _cartId = chosen.Id;
            return Intercept(view.Band, chosen);
        }

        /// Эльфов, пока в партии больше двух сторон, другие ИИ-стороны не трогают.
        bool ElvesFairGame(int targetSide, int sidesLeft)
        {
            if (targetSide != (int)Faction.Elves || Side == Faction.Elves) return true;
            return sidesLeft <= 2;
        }

        /// Первая точка пути обоза, куда отряд успеет раньше него.
        public V3 Intercept(List<V3> band, CartSighting cart)
        {
            if (cart.Ahead.Count == 0) return cart.At;
            var centre = BandPoint(band) ?? Anchor ?? cart.At;
            var walked = cart.At;
            float cartTime = 0f;
            float cartSpeed = Math.Max(1f, cart.Speed);
            foreach (var point in cart.Ahead)
            {
                cartTime += walked.FlatDistance(point) / cartSpeed;
                walked = point;
                float bandTime = centre.FlatDistance(point) / UnitStats.BaseSpeed;
                if (bandTime <= cartTime) return point;
            }
            return cart.Ahead[cart.Ahead.Count - 1];
        }

        static CartSighting CartById(WarbandView view, int id)
        {
            if (id < 0) return null;
            foreach (var cart in view.Carts)
                if (cart.Id == id) return cart;
            return null;
        }

        bool Arrived(List<V3> band, V3 here)
        {
            if (Route.Count > 0) return false;
            var goal = Goal ?? here;
            if (here.Distance(goal) <= AiStats.ArriveRadius) return true;
            var centre = Centre(band);
            return centre.HasValue && centre.Value.Distance(goal) <= AiStats.ArriveRadius;
        }

        void StandDown(List<V3> band, PathFinder path)
        {
            var here = Anchor ?? Base;
            if (here.Distance(Base) > AiStats.ArriveRadius)
            {
                if (State != WarbandState.Return) GoHome(band, path);
                return;
            }
            SetState(WarbandState.Hold, band);
            Route.Clear();
            Goal = Base;
        }

        void GoHome(List<V3> band, PathFinder path)
        {
            SetState(WarbandState.Return, band);
            SetRoute(band, Base, path);
        }

        /// Середина не сдвинулась на 2 м за 24 с похода — набег отменяется.
        bool IsStuck(List<V3> band)
        {
            var centre = Centre(band);
            if (!centre.HasValue) return false;
            var was = _lastCentre ?? centre.Value;
            if (centre.Value.Distance(was) >= AiStats.StuckStep)
            {
                _lastCentre = centre;
                _stuckT = 0f;
                return false;
            }
            _stuckT += AiStats.WarbandThink;
            if (_stuckT < AiStats.StuckSeconds) return false;
            _lastCentre = centre;
            _stuckT = 0f;
            return true;
        }

        static bool Spent(List<V3> band)
        {
            return band.Count < AiStats.GarrisonSize * AiStats.RetreatFraction;
        }

        /// Ближайший к дому враг, стоящий у своей постройки или батрака.
        public V3? HomeThreat(WarbandView view)
        {
            V3? best = null;
            float bestGap = float.MaxValue;
            foreach (var enemy in view.Fighters)
            {
                if (!Factions.Hostile((int)Side, enemy.Side)) continue;
                float fromBase = enemy.At.FlatDistance(Base);
                if (fromBase > AiStats.DefendRange) continue;
                foreach (var post in view.Posts)
                {
                    if (enemy.At.FlatDistance(post) > AiStats.DefendRadius) continue;
                    if (fromBase < bestGap)
                    {
                        bestGap = fromBase;
                        best = enemy.At;
                    }
                    break;
                }
            }
            return best;
        }

        bool EnemyNear(WarbandView view, V3 point)
        {
            foreach (var enemy in view.Fighters)
                if (Factions.Hostile((int)Side, enemy.Side) && point.Distance(enemy.At) <= AiStats.FightRadius)
                    return true;
            return false;
        }

        void SetRoute(List<V3> band, V3 target, PathFinder path)
        {
            var here = BandPoint(band) ?? Anchor ?? target;
            Route.Clear();
            var found = path != null ? path(here, target) : null;
            if (found != null)
                for (int i = 1; i < found.Count; i++) Route.Add(found[i]);
            if (Route.Count == 0) Route.Add(target);
            Goal = target;
            _stuckT = 0f;
            _lastCentre = Centre(band);
        }

        void SetState(WarbandState state, List<V3> band)
        {
            if (State == state) return;
            State = state;
            _stuckT = 0f;
            _lastCentre = Centre(band);
        }

        /// Точка маршрута пройдена: по середине отряда (8 м), без отряда — по ближайшему бойцу (5 м).
        static bool Passed(List<V3> band, V3? centre, V3 point)
        {
            if (!centre.HasValue)
            {
                float best = float.MaxValue;
                foreach (var unit in band) best = Math.Min(best, unit.FlatDistance(point));
                return best <= AiStats.WaypointReached;
            }
            return centre.Value.FlatDistance(point) <= AiStats.BandReached;
        }

        public static V3? Centre(List<V3> band)
        {
            if (band.Count == 0) return null;
            float x = 0f, y = 0f, z = 0f;
            foreach (var unit in band)
            {
                x += unit.X;
                y += unit.Y;
                z += unit.Z;
            }
            return new V3(x / band.Count, y / band.Count, z / band.Count);
        }

        /// Боец, ближайший к середине: середина растянутого строя может висеть над обрывом.
        public static V3? BandPoint(List<V3> band)
        {
            var centre = Centre(band);
            if (!centre.HasValue) return null;
            var best = centre.Value;
            float closest = float.MaxValue;
            foreach (var unit in band)
            {
                float gap = unit.FlatDistance(centre.Value);
                if (gap < closest)
                {
                    closest = gap;
                    best = unit;
                }
            }
            return best;
        }

        /// Якорь — в 14 м впереди отряда вдоль маршрута, а не на углу пути.
        public static V3 LeadAlong(V3? centre, List<V3> route, V3 fallback)
        {
            if (route.Count == 0) return fallback;
            if (!centre.HasValue) return route[0];
            float left = AiStats.LeadDistance;
            var from = centre.Value;
            foreach (var point in route)
            {
                float step = from.FlatDistance(point);
                if (step >= left)
                {
                    var to = (point - from).Flat();
                    if (to.Length() < 0.01f) return point;
                    var lead = from + to.Normalized() * left;
                    return new V3(lead.X, point.Y, lead.Z);
                }
                left -= step;
                from = point;
            }
            return from;
        }

        static V3 Course(V3? centre, List<V3> route)
        {
            if (route.Count == 0) return new V3(0f, 0f, 0f);
            var from = centre ?? route[0];
            var course = (route[0] - from).Flat();
            if (course.Length() < 1f && route.Count > 1) course = (route[1] - route[0]).Flat();
            return course;
        }
    }
}
