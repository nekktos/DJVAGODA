// Персонаж игрока (шаг 3 «Персонаж»): ввод — в ядро, скорость — в CharacterController.
//
// Движение считает владелец (модель прав Godot-версии). Сеть (Netcode) ляжет
// поверх: этот компонент станет ведомым NetworkBehaviour'ом владельца, а
// хост будет считать здоровье, урон и сделки. Пока — одиночная проверка
// ходьбы по миру WorldBuilder.
using DjvaGoda.Core;
using UnityEngine;

namespace DjvaGoda.Game
{
    [RequireComponent(typeof(CharacterController))]
    public class PlayerCharacter : MonoBehaviour
    {
        /// Радиан поворота на пиксель мыши.
        public const float MouseSensitivity = 0.0025f;
        public const float PitchLimit = 1.3f;

        public Faction Side = Faction.Guard;
        public readonly Vitals Vitals = new Vitals();
        public readonly BodyState Body = new BodyState();
        public readonly SpellState Spells = new SpellState();
        public readonly Kit Kit = new Kit();
        readonly CharacterMotor _motor = new CharacterMotor();
        readonly Bandaging _bandaging = new Bandaging();
        CharacterController _controller;

        /// Поворот и наклон головы в ядре: yaw — как у Godot, «вперёд» — −Z.
        public float Yaw;
        public float Pitch;
        public bool Mounted;
        /// Ввод героя ИИ; пусто — ввод игрока.
        public MotorInput? Scripted;
        public bool LocalControl = true;

        public V3 Feet { get { return transform.position.ToCore(); } }
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
        }

        /// Сторону назначают после AddComponent (Awake уже прошёл) — снаряжение узнаёт её здесь.
        void Start() { Kit.Side = Side; }

        void Update()
        {
            float delta = Time.deltaTime;
            var input = Scripted ?? ReadInput();
            if (Scripted == null && LocalControl && Cursor.lockState == CursorLockMode.Locked)
            {
                var look = GameInput.Look();
                // Мышь вправо — поворот вправо: в Unity это рост угла Y, в ядре — убыль yaw.
                Yaw -= look.x * MouseSensitivity;
                Pitch = Mathf.Clamp(Pitch + look.y * MouseSensitivity, -PitchLimit, PitchLimit);
            }
            bool rallied = Spells.Rally > 0f;
            bool paralysed = Spells.Paralysis > 0f;
            var velocity = _motor.Step(input, delta, Yaw, _controller.isGrounded, Side, Vitals, Body, paralysed, Mounted, rallied);
            var move = velocity.ToUnity();
            // На земле — лёгкий прижим, иначе isGrounded мигает на спуске.
            if (_controller.isGrounded && move.y <= 0f) move.y = -2f;
            _controller.Move(move * delta);
            transform.rotation = CoreSpace.YawToRotation(Yaw);

            float flat = new Vector2(_controller.velocity.x, _controller.velocity.z).magnitude;
            if (_bandaging.Tick(delta, Body.Bleeding, Scripted == null && GameInput.Held("bandage"), flat))
                Body.ApplyBandage();
        }

        MotorInput ReadInput()
        {
            if (!LocalControl || Cursor.lockState != CursorLockMode.Locked) return new MotorInput();
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
