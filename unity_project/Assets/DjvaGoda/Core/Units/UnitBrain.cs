// Боец: кого бить, куда встать, как не толкаться (перенос units/unit.gd).
//
// Боец видит врага в радиусе вступления (14 м, лучник 32, чемпион 20), но
// гонится за ним только в пределах поводка вокруг дома или якоря отряда.
// Без цели идёт на своё место в строю: за командиром-игроком, за якорем
// отряда ИИ или домой. Лучник стоит в строю на 7 м позади. Движение
// (физика, путь по навигации) — Unity-слой.
using System;
using System.Collections.Generic;

namespace DjvaGoda.Core
{
    /// Кто рядом: живой игрок, боец, постройка или обоз — с id для Unity-слоя.
    public struct Sighting
    {
        public readonly int Id;
        public readonly V3 At;
        public readonly int Side;
        /// Постройка: её полуразмер удлиняет досягаемость удара.
        public readonly BuildingKind? Building;

        public Sighting(int id, V3 at, int side, BuildingKind? building)
        {
            Id = id;
            At = at;
            Side = side;
            Building = building;
        }
    }

    public class UnitBrain
    {
        public UnitKind Kind;
        public int Side;
        public int Slot;
        public V3 Home;
        /// 0 — поводка нет (гонится за кем видит).
        public float Leash;
        public bool AiLed;
        public V3 AiAnchor;
        public float AiYaw;
        public FormationKind AiFormation = FormationKind.Line;
        public float Cooldown;
        float _charmLeft;
        int _charmHome = -1;

        public UnitBrain(UnitKind kind, int side)
        {
            Kind = kind;
            Side = side;
        }

        public bool IsArcher { get { return Kind == UnitKind.Archer; } }
        public bool Charmed { get { return _charmLeft > 0f; } }

        /// Паралич злодея очаровывает бойца: он воюет за злодея, пока не спадёт.
        public void Charm(int newSide, float seconds, V3 here)
        {
            if (_charmLeft <= 0f) _charmHome = Side;
            Side = newSide;
            _charmLeft = Math.Max(_charmLeft, seconds);
            AiLed = false;
            Home = here;
            Leash = 0f;
        }

        public void Tick(float delta)
        {
            Cooldown = Math.Max(0f, Cooldown - delta);
            if (_charmLeft <= 0f) return;
            _charmLeft -= delta;
            if (_charmLeft <= 0f && _charmHome >= 0)
            {
                Side = _charmHome;
                _charmHome = -1;
            }
        }

        /// Ближайший враг в радиусе вступления.
        public Sighting? FindTarget(V3 here, IEnumerable<Sighting> around)
        {
            Sighting? best = null;
            float bestDistance = UnitStats.EngageRange(Kind);
            foreach (var other in around)
            {
                // Сторона неизвестна — не цель (у Godot-версии так же).
                if (other.Side < 0) continue;
                if (!Factions.Hostile(Side, other.Side)) continue;
                float d = here.Distance(other.At);
                if (d < bestDistance)
                {
                    bestDistance = d;
                    best = other;
                }
            }
            return best;
        }

        public bool WithinLeash(V3 point)
        {
            if (Leash <= 0f) return true;
            var centre = AiLed ? AiAnchor : Home;
            return centre.Distance(point) <= Leash;
        }

        /// Цель, за которой боец пойдёт сейчас: в радиусе вступления и в пределах поводка.
        public Sighting? Engage(V3 here, IEnumerable<Sighting> around)
        {
            var target = FindTarget(here, around);
            if (!target.HasValue || !WithinLeash(target.Value.At)) return null;
            return target;
        }

        public FormationKind Formation(FormationKind? commanderFormation)
        {
            if (commanderFormation.HasValue) return commanderFormation.Value;
            return AiLed ? AiFormation : FormationKind.Line;
        }

        /// Место в строю от якоря: лучник — на 7 м позади своего ряда.
        public V3 FormationOffset(FormationKind formation)
        {
            var offset = Formations.SlotOffset(formation, Slot);
            if (IsArcher) offset = offset + new V3(0f, 0f, -UnitStats.ArcherRear);
            return offset;
        }

        /// Повернуть смещение на yaw вокруг вертикали — как Quaternion.Euler(0, yaw°, 0)
        /// в Unity: при yaw > 0 «вперёд» (+Z) уходит вправо (+X).
        public static V3 Rotate(V3 offset, float yaw)
        {
            float c = (float)Math.Cos(yaw), s = (float)Math.Sin(yaw);
            return new V3(offset.X * c + offset.Z * s, offset.Y, -offset.X * s + offset.Z * c);
        }

        /// Куда идти без цели: к месту за командиром-игроком, за якорем отряда ИИ, домой или стоять.
        public V3 IdleDestination(V3 here, V3? commanderAnchor, float commanderYaw, FormationKind? commanderFormation)
        {
            if (commanderAnchor.HasValue)
                return commanderAnchor.Value + Rotate(FormationOffset(Formation(commanderFormation)), commanderYaw);
            if (AiLed) return AiAnchor + Rotate(FormationOffset(AiFormation), AiYaw);
            if (Leash > 0f) return Home;
            return here;
        }

        /// С какого расстояния бьёт: лучник — 24 м, по постройке — плюс её полуразмер.
        public float ReachOf(Sighting? target)
        {
            if (!target.HasValue) return UnitStats.StrikeRange;
            if (IsArcher) return UnitStats.ArcherRange;
            if (target.Value.Building.HasValue)
            {
                var size = Res.BuildingSize(target.Value.Building.Value);
                return UnitStats.StrikeRange + Math.Max(size.X, size.Z) * 0.5f;
            }
            return UnitStats.StrikeRange;
        }

        /// Ударить, если откат прошёл и руки целы. true — удар (или выстрел) состоялся.
        public bool TryStrike(bool armsWork)
        {
            if (Cooldown > 0f || !armsWork) return false;
            Cooldown = UnitStats.StrikeCooldown(Kind);
            return true;
        }

        public float MoveSpeed(FormationKind formation, float woundScale)
        {
            if (Kind == UnitKind.Beast || Kind == UnitKind.Champion) return UnitStats.Speed(Kind) * woundScale;
            return UnitStats.Speed(Kind) * Formations.SpeedScale(formation) * woundScale;
        }

        /// Лучнику нужны обе руки, мечнику — хотя бы одна.
        public static bool ArmsWork(bool archer, bool leftDown, bool rightDown)
        {
            return archer ? !leftDown && !rightDown : !leftDown || !rightDown;
        }

        /// Без ноги — ползком: скорость ползущего, делённая на обычную.
        public static float WoundSpeedScale(int legsDown)
        {
            if (legsDown >= 2) return BodyState.CrawlSpeedBoth / UnitStats.BaseSpeed;
            if (legsDown == 1) return BodyState.CrawlSpeedOne / UnitStats.BaseSpeed;
            return 1f;
        }

        /// Расталкивание соседей ближе 1.7 м.
        public static V3 Separation(V3 here, IEnumerable<V3> neighbours)
        {
            var push = new V3(0f, 0f, 0f);
            foreach (var other in neighbours)
            {
                var away = (here - other).Flat();
                float distance = away.Length();
                if (distance <= 0.01f || distance >= UnitStats.SeparationRadius) continue;
                push = push + away.Normalized() * (1f - distance / UnitStats.SeparationRadius);
            }
            return push * UnitStats.SeparationForce;
        }

        /// Сложить желаемый ход с расталкиванием: толчок против хода отбрасывается
        /// (иначе задние вставали бы за передними), итог — не быстрее 9 м/с.
        public static V3 Steer(V3 desired, V3 push)
        {
            if (desired.Length() > 0.01f)
            {
                var forward = desired.Normalized();
                float against = push.X * forward.X + push.Z * forward.Z;
                if (against < 0f) push = push - forward * against;
            }
            var flat = new V3(desired.X + push.X, 0f, desired.Z + push.Z);
            if (flat.Length() > UnitStats.MaxFlatSpeed) flat = flat.Normalized() * UnitStats.MaxFlatSpeed;
            return flat;
        }
    }
}
