// Персонаж игрока (шаг 3 «Персонаж»): ввод — в ядро, скорость — в CharacterController.
//
// Движение считает владелец (модель прав Godot-версии). Сеть (Netcode) ляжет
// поверх: этот компонент станет ведомым NetworkBehaviour'ом владельца, а
// хост будет считать здоровье, урон и сделки. Пока — одиночная проверка
// ходьбы по миру сцены.
using DjvaGoda.Core;
using UnityEngine;

namespace DjvaGoda.Game
{
    [RequireComponent(typeof(CharacterController))]
    public class PlayerCharacter : Actor
    {
        /// Радиан поворота на пиксель мыши.
        public const float MouseSensitivity = 0.0025f;
        public const float PitchLimit = 1.3f;

        public Faction Faction = Faction.Guard;
        public readonly Vitals Vitals = new Vitals();
        public readonly BodyState Body = new BodyState();
        public readonly SpellState Spells = new SpellState();
        public readonly Kit Kit = new Kit();
        readonly CharacterMotor _motor = new CharacterMotor();
        readonly Bandaging _bandaging = new Bandaging();
        CharacterController _controller;

        /// Поворот и наклон головы: yaw в радианах, растёт вправо; «вперёд» — +Z.
        public float Yaw;
        public float Pitch;
        public bool Mounted;
        /// Ввод героя ИИ; пусто — ввод игрока.
        public MotorInput? Scripted;
        public bool LocalControl = true;
        /// Считать ли движение здесь. Чужого персонажа ведёт присланное положение
        /// (NetPlayer), иначе мотор тянул бы его гравитацией и нулевым вводом.
        public bool Simulate = true;
        /// Перевязка закончена. По сети — заявка хосту (он решает, сколько
        /// бинтов и встала ли кровь); без обработчика — сразу у себя.
        public System.Action Bandaged;

        public V3 Feet { get { return At; } }
        public V3 Velocity { get { return _motor.Velocity; } }
        public bool Running { get { return _motor.Running; } }

        void Awake()
        {
            _controller = GetComponent<CharacterController>();
            _controller.height = 1.8f;
            _controller.radius = 0.35f;
            _controller.center = new Vector3(0f, 0.9f, 0f);
            _controller.stepOffset = 0.4f;
            // Потолок навигации — 45°; круче ходить не должно и персонажу.
            _controller.slopeLimit = 45f;
            // Перемещения короче minMoveDistance CharacterController молча
            // выбрасывает. При тысячах кадров в секунду (фоновый прогон, мощная
            // машина) шаг за кадр меньше миллиметра — персонаж проходил 6% пути.
            _controller.minMoveDistance = 0f;
            HitZone.Humanoid(transform, this);
        }

        /// Сторону назначают после AddComponent (Awake уже прошёл) — снаряжение узнаёт её здесь.
        void Start()
        {
            Kit.Side = Faction;
            Side = (int)Faction;
        }

        public override bool Alive { get { return Vitals.Alive; } }

        /// Попал (у хоста): отметка на прицеле — владельцу.
        public void NoteHit(bool head, bool killed)
        {
            var net = GetComponent<NetPlayer>();
            if (net != null && net.IsSpawned && !net.IsOwner) net.HitRpc(head, killed);
            else
            {
                var combat = GetComponent<PlayerCombat>();
                if (combat != null) combat.ShowHit(head, killed);
            }
        }

        /// Урон по персонажу: доспех, правило стражи для злодея (снаряжённость
        /// источника), ранение по зоне; любой удар срывает каст и паралич.
        public override void TakeDamage(float amount, string zone, WeaponKind? weapon, bool aoe, Actor source)
        {
            if (!Alive) return;
            int gear = 0, armor = 0;
            var hitter = source as PlayerCharacter;
            if (hitter != null)
            {
                gear = hitter.Kit.GearTier;
                armor = hitter.Kit.ArmorTier;
            }
            float taken = DamageRules.ToCharacter(amount, Kit, source != null ? source.Side : -1, gear, armor);
            Vitals.ApplyDamage(taken);
            Body.RegisterHit(zone, taken, weapon);
            Spells.OnDamaged();
        }

        void Update()
        {
            ShowFallen(!Alive);
            // Павший не ходит: встанет по правилам возрождения (Respawn).
            if (!Alive || !Simulate) return;
            float delta = Time.deltaTime;
            // Таймеры заклинаний и ману считает хост (PlayerSpells).
            var input = Scripted ?? ReadInput();
            if (Scripted == null && LocalControl && !GameMode.Strategy && Cursor.lockState == CursorLockMode.Locked)
            {
                var look = GameInput.Look();
                // Мышь вправо — поворот вправо: рост yaw (угла Y в Unity).
                Yaw += look.x * MouseSensitivity;
                Pitch = Mathf.Clamp(Pitch + look.y * MouseSensitivity, -PitchLimit, PitchLimit);
            }
            bool rallied = Spells.Rally > 0f;
            bool paralysed = Spells.Paralysis > 0f;
            var velocity = _motor.Step(input, delta, Yaw, _controller.isGrounded, Faction, Vitals, Body, paralysed, Mounted, rallied);
            var move = velocity.ToUnity();
            // На земле — лёгкий прижим, иначе isGrounded мигает на спуске.
            if (_controller.isGrounded && move.y <= 0f) move.y = -2f;
            _controller.Move(move * delta);
            transform.rotation = CoreSpace.YawToRotation(Yaw);

            float flat = new Vector2(_controller.velocity.x, _controller.velocity.z).magnitude;
            if (_bandaging.Tick(delta, Body.Bleeding, Scripted == null && LocalControl && !GameMode.Strategy && GameInput.Held("bandage"), flat))
            {
                if (Bandaged != null) Bandaged();
                else Body.ApplyBandage();
            }
        }

        bool _shownFallen;

        /// Павший лежит: капсула-заглушка — на боку.
        void ShowFallen(bool fallen)
        {
            if (fallen == _shownFallen) return;
            _shownFallen = fallen;
            var body = transform.Find("Тело");
            if (body == null) return;
            body.localRotation = fallen ? Quaternion.Euler(0f, 0f, 90f) : Quaternion.identity;
            body.localPosition = new Vector3(0f, fallen ? 0.35f : 0.9f, 0f);
        }

        /// Поставить на точку (возрождение): CharacterController помнит своё
        /// положение, без выключения первый Move вернул бы назад.
        public void Teleport(Vector3 at)
        {
            _controller.enabled = false;
            transform.position = at;
            _controller.enabled = true;
            _motor.Velocity = new V3(0f, 0f, 0f);
        }

        MotorInput ReadInput()
        {
            if (!LocalControl || GameMode.Strategy || Cursor.lockState != CursorLockMode.Locked) return new MotorInput();
            var move = GameInput.Move();
            return new MotorInput
            {
                MoveX = move.x,
                MoveY = move.y,
                Run = GameInput.Held("sprint"),
                Jump = GameInput.Pressed("jump"),
                Dash = GameInput.Pressed("dash"),
            };
        }

        /// Направление выстрела: из глаз в точку, куда смотрит камера.
        public V3 AimDirection(Camera camera)
        {
            var straight = Aim.Straight(Yaw, Pitch);
            if (camera == null) return straight;
            var ray = new Ray(camera.transform.position, camera.transform.forward);
            RaycastHit hit;
            var target = Physics.Raycast(ray, out hit, Aim.Range, ~0, QueryTriggerInteraction.Ignore) && hit.collider.transform.root != transform.root
                ? hit.point
                : ray.origin + ray.direction * Aim.Range;
            return Aim.Direction(Feet, Yaw, Pitch, target.ToCore());
        }
    }
}
