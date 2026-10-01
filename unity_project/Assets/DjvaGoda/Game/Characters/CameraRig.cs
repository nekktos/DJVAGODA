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
            if (GameInput.Pressed("toggle_view")) FirstPerson = !FirstPerson;
            // Клик — захватить мышь; Escape — отпустить (меню, окна). Без
            // персонажа (меню сессии) мышь не захватывается: клик — по кнопкам.
            var mouse = UnityEngine.InputSystem.Mouse.current;
            var keyboard = UnityEngine.InputSystem.Keyboard.current;
            if (Target != null && mouse != null && mouse.leftButton.wasPressedThisFrame && Cursor.lockState != CursorLockMode.Locked)
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

        void LateUpdate()
        {
            if (Target == null) return;
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
