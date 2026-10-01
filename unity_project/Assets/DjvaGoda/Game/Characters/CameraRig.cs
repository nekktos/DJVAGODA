// Камера персонажа: из-за правого плеча или от первого лица (клавиша V).
//
// Числа — Godot-версии: опора из-за плеча в 0.65 м вправо и 1.6 м вверх, плечо
// 4.5 м; первое лицо — на уровне глаз. Плечо укорачивается о стену (сфера по
// лучу назад), иначе камера уходила за стены форта и показывала изнанку мира.
using DjvaGoda.Core;
using UnityEngine;

namespace DjvaGoda.Game
{
    public class CameraRig : MonoBehaviour
    {
        public static readonly V3 ThirdPivot = new V3(0.65f, 1.6f, 0f);
        public const float ThirdArm = 4.5f;
        public static readonly V3 FirstPivot = new V3(0f, 1.36f, 0.12f);
        public const float CameraRadius = 0.25f;

        public PlayerCharacter Target;
        public bool FirstPerson;
        Camera _camera;

        // Вид сверху (Tab): точка обзора, высота и поворот камеры.
        public const float StrategyMinHeight = 25f;
        public const float StrategyMaxHeight = 160f;
        Vector3 _focus;
        float _height = 60f;
        float _turn;

        public Camera Camera { get { return _camera; } }

        void Awake()
        {
            _camera = GetComponent<Camera>();
            if (_camera == null) _camera = gameObject.AddComponent<Camera>();
            _camera.nearClipPlane = 0.05f;
            _camera.farClipPlane = 2000f;
        }

        void Update()
        {
            if (Target != null && GameInput.Pressed("toggle_camera"))
            {
                GameMode.Strategy = !GameMode.Strategy;
                if (GameMode.Strategy)
                {
                    _focus = Target.transform.position;
                    _turn = Target.Yaw * Mathf.Rad2Deg;
                    Cursor.lockState = CursorLockMode.None;
                    Cursor.visible = true;
                }
            }
            if (GameMode.Strategy)
            {
                Strategy(Time.unscaledDeltaTime);
                return;
            }
            if (GameInput.Pressed("toggle_view")) FirstPerson = !FirstPerson;
            // Клик — захватить мышь; Escape — отпустить (меню, окна). Без
            // персонажа (меню сессии) мышь не захватывается: клик — по кнопкам.
            var mouse = UnityEngine.InputSystem.Mouse.current;
            var keyboard = UnityEngine.InputSystem.Keyboard.current;
            if (Target != null && !GameMenu.Open && mouse != null && mouse.leftButton.wasPressedThisFrame && Cursor.lockState != CursorLockMode.Locked)
            {
                Cursor.lockState = CursorLockMode.Locked;
                Cursor.visible = false;
            }
            if (keyboard != null && keyboard.escapeKey.wasPressedThisFrame)
            {
                Cursor.lockState = CursorLockMode.None;
                Cursor.visible = true;
            }
        }

        /// Сверху: WASD — двигать точку обзора (быстрее, чем выше), Q/E — вращать, колесо — высота.
        void Strategy(float delta)
        {
            var move = GameInput.Move();
            var turn = Quaternion.Euler(0f, _turn, 0f);
            _focus += turn * new Vector3(move.x, 0f, -move.y) * (_height * 1.2f * delta);
            if (GameInput.Held("cam_rotate_left")) _turn -= 90f * delta;
            if (GameInput.Held("cam_rotate_right")) _turn += 90f * delta;
            var mouse = UnityEngine.InputSystem.Mouse.current;
            if (mouse != null)
            {
                float scroll = mouse.scroll.ReadValue().y;
                if (Mathf.Abs(scroll) > 0.01f)
                    _height = Mathf.Clamp(_height * (scroll > 0f ? 0.9f : 1.1f), StrategyMinHeight, StrategyMaxHeight);
            }
            var turnNow = Quaternion.Euler(0f, _turn, 0f);
            var from = _focus + turnNow * new Vector3(0f, 0f, -_height * 0.55f) + Vector3.up * _height;
            transform.SetPositionAndRotation(from, Quaternion.LookRotation(_focus - from, Vector3.up));
        }

        void LateUpdate()
        {
            if (Target == null || GameMode.Strategy) return;
            var feet = Target.Feet;
            var look = Aim.Straight(Target.Yaw, Target.Pitch).ToUnity();
            var pivotCore = feet + UnitBrain.Rotate(FirstPerson ? FirstPivot : ThirdPivot, Target.Yaw);
            var pivot = pivotCore.ToUnity();
            float arm = FirstPerson ? 0f : ThirdArm;
            if (arm > 0f)
            {
                RaycastHit hit;
                if (Physics.SphereCast(pivot, CameraRadius, -look, out hit, arm, ~0, QueryTriggerInteraction.Ignore)
                    && hit.collider.transform.root != Target.transform.root)
                    arm = Mathf.Max(0.3f, hit.distance);
            }
            transform.SetPositionAndRotation(pivot - look * arm, Quaternion.LookRotation(look, Vector3.up));
        }
    }
}
