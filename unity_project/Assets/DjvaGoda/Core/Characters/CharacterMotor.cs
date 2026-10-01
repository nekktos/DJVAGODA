// Движение персонажа за кадр (перенос player.gd::apply_input).
//
// Считает владелец персонажа (модель прав Godot-версии: клиент ведёт своё
// движение сам). Unity-слой отдаёт ввод и «на земле ли», получает скорость и
// двигает CharacterController. Паралич гасит ввод; бег тратит выносливость
// (верхом — нет); прыжок стоит сил, у эльфов есть второй прыжок в воздухе и
// рывок. Скорость — от ног (протезы, ползком, коляска), клича и лошади.
using System;

namespace DjvaGoda.Core
{
    public struct MotorInput
    {
        /// Ход как у Godot get_vector: X — вправо, Y — назад (вперёд — отрицательный).
        public float MoveX;
        public float MoveY;
        public bool Run;
        public bool Jump;
        public bool Dash;
    }

    public class CharacterMotor
    {
        public const float Gravity = 9.8f;

        public V3 Velocity;
        public bool Running { get; private set; }
        public bool Dashing { get { return _dashLeft > 0f; } }
        int _airJumps;
        float _dashLeft;
        float _dashCooldown;
        V3 _dashDir;

        /// yaw — поворот персонажа (оси Unity: «вперёд» — +Z, yaw растёт вправо).
        public V3 Step(MotorInput input, float delta, float yaw, bool onFloor, Faction side,
            Vitals vitals, BodyState body, bool paralysed, bool mounted, bool rallied)
        {
            float mx = input.MoveX, my = input.MoveY;
            bool jump = input.Jump;
            if (paralysed)
            {
                mx = 0f;
                my = 0f;
                jump = false;
            }
            float moveLength = (float)Math.Sqrt(mx * mx + my * my);
            bool wantsRun = input.Run && moveLength > 0.1f && !mounted && !body.IsCrawling()
                && !body.InWheelchair && !paralysed;
            Running = vitals.TickRun(delta, wantsRun, mounted);

            var mobility = Factions.MobilityOf(side);
            float speed = body.MoveSpeed(Movement.Speed) * SpellEffects.RallySpeedScale(rallied)
                * (mounted ? HorseStats.RideSpeedScale : 1f) * mobility.Speed;
            if (Running) speed *= vitals.RunScale;
            float jumpPower = body.JumpVelocity(Movement.JumpVelocity);

            float vy = Velocity.Y;
            if (onFloor)
            {
                _airJumps = mobility.AirJumps;
                vy = 0f;
                if (jump && jumpPower > 0f && (mounted || vitals.Stamina >= Vitals.StaminaJump) && vitals.TryJump(mounted))
                    vy = jumpPower;
            }
            else
            {
                vy -= Gravity * delta;
                if (jump && _airJumps > 0 && !mounted && jumpPower > 0f && vitals.Stamina >= Vitals.StaminaJump
                    && vitals.TryJump(false))
                {
                    _airJumps--;
                    vy = jumpPower;
                }
            }

            // Ввод: X — вправо, Y — назад (как get_vector Godot); вперёд — +Z.
            var dir = UnitBrain.Rotate(new V3(mx, 0f, -my), yaw).Flat();
            dir = dir.Length() > 1e-4f ? dir.Normalized() : new V3(0f, 0f, 0f);

            _dashCooldown = Math.Max(0f, _dashCooldown - delta);
            if (input.Dash && mobility.Dash && !mounted && _dashCooldown <= 0f && _dashLeft <= 0f && !paralysed
                && !body.IsCrawling() && vitals.Stamina >= Movement.DashStamina)
            {
                _dashDir = dir.Length() > 0.1f ? dir : UnitBrain.Rotate(new V3(0f, 0f, 1f), yaw);
                _dashLeft = Movement.DashTime;
                _dashCooldown = Movement.DashCooldown;
                vitals.SpendStamina(Movement.DashStamina);
            }
            if (_dashLeft > 0f)
            {
                _dashLeft -= delta;
                Velocity = new V3(_dashDir.X * Movement.DashSpeed, vy, _dashDir.Z * Movement.DashSpeed);
            }
            else
            {
                Velocity = new V3(dir.X * speed, vy, dir.Z * speed);
            }
            return Velocity;
        }
    }
}
