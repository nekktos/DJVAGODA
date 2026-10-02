// Звуки мира (перенос audio/sfx.gd): пул 3D-источников и банк клипов из
// Synth. Звук — только у себя: ничего не шлёт по сети, а слушает то, что и
// так видно на каждом пире — здоровье и смерть участников, достройку,
// выстрелы, вспышки заклинаний, шаги фигур и копыта.
//
// Удары и смерти не требуют своих RPC: здоровье участников и так
// синхронизировано, поэтому Sfx раз в кадр сравнивает его с прошлым.
using System.Collections.Generic;
using DjvaGoda.Core;
using UnityEngine;

namespace DjvaGoda.Game
{
    public enum SoundKind
    {
        HitFlesh, HitWood, HitStone, Swing, Bow, Crossbow, Fireball, Explosion,
        Death, BuildDone, Magic, Curse, Notice, Step, Hoof, Squirrel,
    }

    public class Sfx : MonoBehaviour
    {
        public const int Voices = 12;
        public const float HearDistance = 90f;
        /// Шаги и копыта тише и ближе: толпа батраков не должна топать на всю карту.
        const float StepDistance = 25f;
        const int Variants = 4;

        static Sfx _instance;
        /// Сколько звуков сыграно с начала (для тестов).
        public static int Played { get; private set; }
        public static SoundKind? Last { get; private set; }
        /// Выключатель: тесты и сервер без экрана звук не играют.
        public static bool Muted;

        readonly AudioSource[] _voices = new AudioSource[Voices];
        readonly Dictionary<SoundKind, AudioClip[]> _bank = new Dictionary<SoundKind, AudioClip[]>();
        readonly Dictionary<Actor, float> _health = new Dictionary<Actor, float>();
        readonly Dictionary<Actor, bool> _alive = new Dictionary<Actor, bool>();
        readonly Dictionary<BuildingActor, bool> _done = new Dictionary<BuildingActor, bool>();
        readonly Dictionary<CaravanActor, AudioSource> _carts = new Dictionary<CaravanActor, AudioSource>();
        AudioClip _cart;
        int _next;

        public static Sfx Instance
        {
            get
            {
                if (_instance == null)
                {
                    var go = new GameObject("Звук");
                    _instance = go.AddComponent<Sfx>();
                }
                return _instance;
            }
        }

        void Awake()
        {
            _instance = this;
            for (int i = 0; i < Voices; i++)
            {
                var voice = new GameObject("Голос " + i).AddComponent<AudioSource>();
                voice.transform.SetParent(transform, false);
                Spatial(voice, HearDistance);
                _voices[i] = voice;
            }
            Bake();
            if (Ambience.Instance == null) gameObject.AddComponent<Ambience>();
        }

        void OnDestroy() { if (_instance == this) _instance = null; }

        static void Spatial(AudioSource voice, float distance)
        {
            voice.playOnAwake = false;
            voice.spatialBlend = 1f;
            voice.rolloffMode = AudioRolloffMode.Linear;
            voice.minDistance = 2f;
            voice.maxDistance = distance;
            voice.dopplerLevel = 0f;
        }

        void Bake()
        {
            Many(SoundKind.HitFlesh, Synth.HitFlesh);
            Many(SoundKind.HitWood, Synth.HitWood);
            Many(SoundKind.HitStone, Synth.HitStone);
            Many(SoundKind.Swing, Synth.Swing);
            Many(SoundKind.Bow, Synth.Bow);
            Many(SoundKind.Crossbow, Synth.Crossbow);
            Many(SoundKind.Fireball, Synth.Fireball);
            Many(SoundKind.Explosion, Synth.Explosion);
            Many(SoundKind.Death, Synth.Death);
            Many(SoundKind.Step, Synth.Step);
            Many(SoundKind.Hoof, Synth.Hoof);
            Many(SoundKind.Squirrel, Synth.Squirrel);
            _bank[SoundKind.BuildDone] = new[] { Synth.BuildDone() };
            _bank[SoundKind.Magic] = new[] { Synth.Magic() };
            _bank[SoundKind.Curse] = new[] { Synth.Curse() };
            _bank[SoundKind.Notice] = new[] { Synth.Notice() };
            _cart = Synth.Cart();
        }

        void Many(SoundKind kind, System.Func<int, AudioClip> make)
        {
            var clips = new AudioClip[Variants];
            for (int i = 0; i < Variants; i++) clips[i] = make(1000 * (int)kind + i);
            _bank[kind] = clips;
        }

        // --- вход для игры ---------------------------------------------------

        /// Звук в точке мира. Дальше слышимости — не играется вовсе.
        public static void Play(SoundKind kind, Vector3 at, float volume = 1f)
        {
            if (Muted) return;
            Instance.PlayAt(kind, at, volume, false);
        }

        /// Звук «в ушах» (объявления): без места, на полную.
        public static void PlayFlat(SoundKind kind, float volume = 1f)
        {
            if (Muted) return;
            Instance.PlayAt(kind, Vector3.zero, volume, true);
        }

        public static void ForWeapon(WeaponKind kind, Vector3 at)
        {
            if (kind == WeaponKind.Bow) Play(SoundKind.Bow, at);
            else if (kind == WeaponKind.Crossbow) Play(SoundKind.Crossbow, at);
            else if (kind == WeaponKind.Spell) Play(SoundKind.Fireball, at);
        }

        public static void ForSpell(AbilityKind kind, Vector3 at)
        {
            bool villain = kind == AbilityKind.Paralysis || kind == AbilityKind.Wither || kind == AbilityKind.Blind;
            Play(villain ? SoundKind.Curse : SoundKind.Magic, at, 0.8f);
            if (kind == AbilityKind.Summon) Play(SoundKind.Squirrel, at);
        }

        /// Шаг фигуры или копыто: тихо и только рядом с ушами.
        public static void Footfall(bool hoof, Vector3 at)
        {
            if (Muted || _instance == null) return;
            var ears = Ears();
            if (ears == null || (ears.position - at).sqrMagnitude > StepDistance * StepDistance) return;
            _instance.PlayAt(hoof ? SoundKind.Hoof : SoundKind.Step, at, hoof ? 0.55f : 0.35f, false, StepDistance);
        }

        static AudioListener _ears;

        /// Уши — слушатель на камере; нет его — вешается на главную камеру.
        public static Transform Ears()
        {
            if (_ears != null && _ears.isActiveAndEnabled) return _ears.transform;
            _ears = FindAnyObjectByType<AudioListener>();
            if (_ears != null) return _ears.transform;
            var cam = Camera.main;
            if (cam == null) return null;
            _ears = cam.gameObject.AddComponent<AudioListener>();
            return cam.transform;
        }

        void PlayAt(SoundKind kind, Vector3 at, float volume, bool flat, float distance = HearDistance)
        {
            AudioClip[] clips;
            if (!_bank.TryGetValue(kind, out clips)) return;
            if (!flat)
            {
                var ears = Ears();
                if (ears != null && (ears.position - at).sqrMagnitude > distance * distance) return;
            }
            // Свободный голос, иначе — по кругу (самый старый обрывается).
            AudioSource voice = null;
            for (int i = 0; i < Voices && voice == null; i++)
                if (!_voices[(_next + i) % Voices].isPlaying) voice = _voices[(_next + i) % Voices];
            if (voice == null) voice = _voices[_next];
            _next = (_next + 1) % Voices;
            voice.transform.position = at;
            voice.spatialBlend = flat ? 0f : 1f;
            voice.maxDistance = distance;
            voice.clip = clips[Random.Range(0, clips.Length)];
            voice.volume = volume;
            voice.pitch = Random.Range(0.92f, 1.08f);
            voice.Play();
            Played++;
            Last = kind;
        }

        // --- слежка за миром -------------------------------------------------

        void Update()
        {
            var seen = new List<Actor>(Actor.All);
            foreach (var actor in seen)
            {
                if (actor == null) continue;
                float hp = HealthOf(actor);
                bool alive = actor.Alive;
                float was;
                if (_health.TryGetValue(actor, out was) && hp < was - 0.01f && _alive[actor])
                    Play(Impact(actor), actor.transform.position + Vector3.up, 0.8f);
                if (_alive.ContainsKey(actor) && _alive[actor] && !alive && !(actor is BuildingActor) && !(actor is CaravanActor))
                    Play(SoundKind.Death, actor.transform.position);
                _health[actor] = hp;
                _alive[actor] = alive;

                var building = actor as BuildingActor;
                if (building != null && building.State != null)
                {
                    bool done;
                    if (_done.TryGetValue(building, out done) && !done && building.State.Done)
                        Play(SoundKind.BuildDone, building.transform.position, 0.7f);
                    _done[building] = building.State.Done;
                }
                var cart = actor as CaravanActor;
                if (cart != null) Rumble(cart);
            }
            Forget();
        }

        /// Обоз скрипит, пока едет.
        void Rumble(CaravanActor cart)
        {
            AudioSource source;
            if (!_carts.TryGetValue(cart, out source) || source == null)
            {
                source = cart.gameObject.AddComponent<AudioSource>();
                Spatial(source, 35f);
                source.clip = _cart;
                source.loop = true;
                source.volume = 0.8f;
                _carts[cart] = source;
            }
            bool rolling = !Muted && cart.Alive && cart.Trip != null && !cart.Trip.Halted && !cart.Trip.Waiting
                && cart.Trip.State != CaravanState.Finished;
            if (rolling && !source.isPlaying) source.Play();
            else if (!rolling && source.isPlaying) source.Stop();
        }

        /// Ушедших из мира — забыть, чтобы словари не росли.
        void Forget()
        {
            if (_health.Count < Actor.All.Count + 64) return;
            var gone = new List<Actor>();
            foreach (var key in _health.Keys)
                if (key == null || !Actor.All.Contains(key)) gone.Add(key);
            foreach (var key in gone)
            {
                _health.Remove(key);
                _alive.Remove(key);
                var b = key as BuildingActor;
                if (!ReferenceEquals(b, null)) _done.Remove(b);
                var c = key as CaravanActor;
                if (!ReferenceEquals(c, null)) _carts.Remove(c);
            }
        }

        static SoundKind Impact(Actor actor)
        {
            var building = actor as BuildingActor;
            if (building != null)
                return building.State.Grade == (int)Grade.Wood ? SoundKind.HitWood : SoundKind.HitStone;
            if (actor is CaravanActor) return SoundKind.HitWood;
            return SoundKind.HitFlesh;
        }

        public static float HealthOf(Actor actor)
        {
            var player = actor as PlayerCharacter;
            if (player != null) return player.Vitals.Health;
            var unit = actor as UnitAgent;
            if (unit != null) return unit.Health;
            var hand = actor as LabourerAgent;
            if (hand != null) return hand.Health;
            var horse = actor as HorseActor;
            if (horse != null) return horse.Health;
            var building = actor as BuildingActor;
            if (building != null) return building.State != null ? building.State.Health : 0f;
            var cart = actor as CaravanActor;
            if (cart != null) return cart.Trip != null ? cart.Trip.Health : 0f;
            return 0f;
        }
    }
}
