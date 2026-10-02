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
        /// Трофеи — чужие руки, ноги, глаза (TrophyKind): плата за некротические протезы.
        public readonly int[] Trophies = new int[3];
        /// Служба стража у командира и задания эльфа у старейшины (у хоста; владельцу — NetPlayer).
        public readonly ServiceRecord Service = new ServiceRecord();
        public readonly ElfTaskRecord Tasks = new ElfTaskRecord();
        /// Профиль человека (у хоста): ключ сохранения вместе со стороной. Пусто — ИИ.
        public string Profile = "";
        bool _wasAlive = true;
        readonly CharacterMotor _motor = new CharacterMotor();
        readonly Bandaging _bandaging = new Bandaging();
        CharacterController _controller;

        /// Поворот и наклон головы: yaw в радианах, растёт вправо; «вперёд» — +Z.
        public float Yaw;
        public float Pitch;
        public bool Mounted;
        /// На какой лошади едет (у хоста); владельцу едет только Mounted (NetPlayer).
        public HorseActor Horse;
        /// Приказы отряду (у хоста; Squads): строй, стоять на точке или идти за мной.
        public FormationKind SquadFormation = FormationKind.Line;
        public bool SquadHold;
        public V3 SquadRally;
        public float SquadRallyYaw;
        /// Сколько лошадей запрягать в следующий обоз (выбирают в конюшне).
        public int HarnessSize = Builder.HarnessSize;
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
            int severedBefore = Body.SeveredMask;
            int eyesBefore = Body.EyesLost;
            Body.RegisterHit(zone, taken, weapon);
            Spells.OnDamaged();
            // Оторванное падает на землю: трофей — тому, кто дойдёт и поднимет.
            int fresh = Body.SeveredMask & ~severedBefore;
            for (int i = 0; i < 4; i++)
                if ((fresh & (1 << i)) != 0) Pickup.DropLimb(Feet + new V3(0.6f * (i - 1.5f), 0.2f, 0f), (Limb)i);
            // Глаз падать нечем — засчитывается сразу тому, кто выбил.
            if (hitter != null && Body.EyesLost > eyesBefore) hitter.Trophies[(int)TrophyKind.Eyes] += Body.EyesLost - eyesBefore;
        }

        void Update()
        {
            ShowFallen(!Alive);
            // Пал (от удара или от крови) — у хоста всё с тела падает кучей.
            if (_wasAlive && !Alive && MatchNet.Hosting)
            {
                // Тело остаётся лежать трупом; сам персонаж до возрождения не виден.
                Corpses.Spawn(transform.position, Yaw * Mathf.Rad2Deg, Corpses.HeroLook, (int)Faction, Body.SeveredMask);
                DropBelongings();
                // Павший всадник падает с седла: лошадь остаётся рядом с телом.
                if (Horse != null) Horse.Dismount(Feet + new V3(1.5f, 0f, 0f));
                Horse = null;
                Mounted = false;
            }
            _wasAlive = Alive;
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

        /// Всё с тела — кучей на месте смерти (ответ автора от 29.09): ноша
        /// стороны при себе, оружие и доспех, бинты, зелья, стрелы.
        void DropBelongings()
        {
            var pile = LootPile.FromBody(Treasury.Of(Faction).DropCarried(), Kit, Body);
            Kit.GearTier = 0;
            Kit.ArmorTier = 0;
            Kit.PotionsHeal = 0;
            Kit.PotionsMana = 0;
            Kit.Arrows = 0;
            Body.Bandages = 0;
            Pickup.Drop(Feet + new V3(0f, 0.6f, 0f), pile);
        }

        bool _shownFallen;

        /// Павший: вместо него лежит труп (Corpses), сам он до возрождения скрыт.
        void ShowFallen(bool fallen)
        {
            if (fallen == _shownFallen) return;
            _shownFallen = fallen;
            var body = transform.Find("Тело");
            if (body != null) body.gameObject.SetActive(!fallen);
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
