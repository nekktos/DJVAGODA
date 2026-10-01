// Боец в мире (перенос unit.gd): мозг ядра решает цель и место в строю,
// PathFollower — дорогу, CharacterController — шаг. Считает только хост.
using DjvaGoda.Core;
using UnityEngine;

namespace DjvaGoda.Game
{
    [RequireComponent(typeof(CharacterController))]
    public class UnitAgent : Actor
    {
        public UnitBrain Brain;
        public float Health;
        public NavWorld Nav;
        /// Командир-игрок, за которым идёт строй; null — ведёт ИИ или стоит дома.
        public PlayerCharacter Commander;
        public FormationKind CommanderFormation = FormationKind.Line;
        /// Сколько ещё живёт (волк призыва — минуту); ноль и меньше — без срока.
        public float Lifetime;
        /// Распорядитель стражи или старейшина эльфов: встаёт сам и в счёт живых стороны не идёт.
        public bool Champion;

        readonly PathFollower _follower = new PathFollower();
        CharacterController _controller;
        float _fall;

        public override bool Alive { get { return Health > 0f; } }

        public void Setup(UnitKind kind, int side, int slot, V3 home, float leash)
        {
            Brain = new UnitBrain(kind, side) { Slot = slot, Home = home, Leash = leash };
            Side = side;
            Health = UnitStats.Health(kind);
        }

        void Awake()
        {
            _controller = GetComponent<CharacterController>();
            _controller.height = 1.8f;
            _controller.radius = 0.4f;
            _controller.center = new Vector3(0f, 0.9f, 0f);
            _controller.slopeLimit = 45f;
            // Перемещения короче minMoveDistance CharacterController молча
            // выбрасывает. При тысячах кадров в секунду (фоновый прогон, мощная
            // машина) шаг за кадр меньше миллиметра — персонаж проходил 6% пути.
            _controller.minMoveDistance = 0f;
            HitZone.Humanoid(transform, this);
        }

        void Update()
        {
            if (Brain == null || !Alive) return;
            float delta = Time.deltaTime;
            if (Lifetime > 0f)
            {
                Lifetime -= delta;
                if (Lifetime <= 0f)
                {
                    Agents.Remove(gameObject);
                    return;
                }
            }
            Brain.Tick(delta);
            Side = Brain.Side;
            var here = At;
            var target = Brain.Engage(here, Actor.Around(here, UnitStats.EngageRange(Brain.Kind) + 1f, this));
            V3 destination;
            bool facingTarget = false;
            if (target.HasValue)
            {
                destination = target.Value.At;
                facingTarget = true;
            }
            else
            {
                V3? anchor = null;
                float yaw = 0f;
                if (Commander != null)
                {
                    anchor = Commander.Feet;
                    yaw = Commander.Yaw;
                }
                destination = Brain.IdleDestination(here, anchor, yaw, Commander != null ? CommanderFormation : (FormationKind?)null);
            }

            PathFinder finder = Nav != null && Nav.Ready ? Nav.Finder : null;
            var step = _follower.NextStep(here, destination, finder, Nav != null ? (System.Func<V3, V3>)Nav.ClosestPoint : null);
            float distance = here.FlatDistance(destination);
            float stopAt = facingTarget ? Brain.ReachOf(target) : UnitStats.SlotTolerance;
            var desired = new V3(0f, 0f, 0f);
            bool moving = distance > stopAt;
            if (moving)
            {
                var to = (step - here).Flat();
                if (to.Length() < 0.01f) to = (destination - here).Flat();
                var formation = Brain.Formation(Commander != null ? CommanderFormation : (FormationKind?)null);
                desired = to.Normalized() * Brain.MoveSpeed(formation, 1f);
                transform.rotation = CoreSpace.YawToRotation(Mathf.Atan2(to.X, to.Z));
            }
            else if (facingTarget)
            {
                Strike(target.Value);
            }
            var neighbours = new System.Collections.Generic.List<V3>();
            foreach (var actor in Actor.All)
                if (actor is UnitAgent && actor != this && actor.At.FlatDistance(here) < UnitStats.SeparationRadius) neighbours.Add(actor.At);
            var flat = UnitBrain.Steer(desired, UnitBrain.Separation(here, neighbours));
            _fall = _controller.isGrounded ? -2f : _fall - CharacterMotor.Gravity * delta;
            _controller.Move(new V3(flat.X, _fall, flat.Z).ToUnity() * delta);
            _follower.NoteProgress(delta, moving, At, destination);
        }

        void Strike(Sighting target)
        {
            if (!Brain.TryStrike(true)) return;
            var victim = Actor.ById(target.Id);
            if (victim == null) return;
            // Лучник стреляет стрелой (полёт — ProjectileFlight); пока — удар без полёта.
            var weapon = Brain.IsArcher ? WeaponKind.Bow : WeaponKind.Sword;
            victim.TakeDamage(UnitStats.StrikeDamage(Brain.Kind), "torso", weapon, false, this);
        }

        public override void TakeDamage(float amount, string zone, WeaponKind? weapon, bool aoe, Actor source)
        {
            if (!Alive) return;
            var formation = Brain.Formation(Commander != null ? CommanderFormation : (FormationKind?)null);
            Health = Mathf.Max(0f, Health - DamageRules.ToUnit(amount, formation, aoe, weapon));
            if (!Alive) Agents.Remove(gameObject);
        }
    }
}
