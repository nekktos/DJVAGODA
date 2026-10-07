// Загрузчик сцены: находит мир (собран в редакторе и лежит в сцене) и камеру
// и — в одиночном режиме — ставит персонажа на точке своей стороны.
//
// В сетевой сцене (Networked) персонажей спавнит хост (NetSession), камера
// ждёт своего. Проверки ходьбы берут сетевую сцену и ставят персонажа сами
// (SpawnLocal).
using DjvaGoda.Core;
using UnityEngine;

namespace DjvaGoda.Game
{
    public class Bootstrap : MonoBehaviour
    {
        public Faction Side = Faction.Guard;
        public bool Networked;

        public World World { get; private set; }
        public NavWorld Nav { get; private set; }
        public PlayerCharacter Player { get; private set; }
        public CameraRig Rig { get; private set; }

        void Awake()
        {
            // Журнал тестера (Player.log): обычные строки — без стека вызовов.
            // Со стеком каждая строка разрасталась в десять, и отчёт в 360 строк
            // нёс три десятка сообщений (playtest-10). Ошибки — со стеком, как были.
            if (!Application.isEditor)
            {
                Application.SetStackTraceLogType(LogType.Log, StackTraceLogType.None);
                Application.SetStackTraceLogType(LogType.Warning, StackTraceLogType.None);
            }
            World = Object.FindAnyObjectByType<World>();
            if (World == null) Debug.LogError("В сцене нет мира: ДжваГода → Собрать мир.");
            else Nav = World.GetComponent<NavWorld>();

            // Камера — в сцене (видно в окне Game и без Play); нет — своя.
            Rig = Object.FindAnyObjectByType<CameraRig>();
            if (Rig == null)
            {
                var eye = new GameObject("Камера");
                eye.tag = "MainCamera";
                Rig = eye.AddComponent<CameraRig>();
            }
            if (Rig.GetComponent<Hud>() == null) Rig.gameObject.AddComponent<Hud>();
            if (Rig.GetComponent<GameMenu>() == null) Rig.gameObject.AddComponent<GameMenu>();
            if (Rig.GetComponent<Onboarding>() == null) Rig.gameObject.AddComponent<Onboarding>();
            if (Rig.GetComponent<GrassField>() == null) Rig.gameObject.AddComponent<GrassField>();
            if (!Networked) SpawnLocal(Side);
        }

        /// Персонаж без сети — на точке стороны, под камерой.
        public PlayerCharacter SpawnLocal(Faction side)
        {
            var root = new GameObject("Игрок");
            root.transform.position = (Factions.Spawn[(int)side] + new V3(0f, 1f, 0f)).ToUnity();
            AddBody(root.transform, side);
            Player = root.AddComponent<PlayerCharacter>();
            Player.Faction = side;
            root.AddComponent<PlayerCombat>();
            root.AddComponent<PlayerSpells>();
            root.AddComponent<WeaponView>();
            root.AddComponent<Builder>();
            root.AddComponent<Shop>();
            Rig.Target = Player;
            return Player;
        }

        /// Тело персонажа — фигура стороны (Figure): ноги в начале координат
        /// корня, там же, где стоит CharacterController.
        public static void AddBody(Transform root, Faction side)
        {
            Figure.Build(root, FigureLook.Hero(side));
        }
    }
}
