// Загрузчик сцены: мир из ядра, персонаж на точке своей стороны, камера.
//
// Одиночная проверка шагов 3 и 5 (персонаж ходит по миру) до сети: на сцене
// нужен один объект с этим компонентом. Сеть заменит «персонажа сразу» на
// спавн с хоста.
using DjvaGoda.Core;
using UnityEngine;

namespace DjvaGoda.Game
{
    public class Bootstrap : MonoBehaviour
    {
        public Faction Side = Faction.Guard;

        public WorldBuilder World { get; private set; }
        public PlayerCharacter Player { get; private set; }
        public CameraRig Rig { get; private set; }

        void Awake()
        {
            World = new GameObject("Мир").AddComponent<WorldBuilder>();
            Light();

            var root = new GameObject("Игрок");
            root.transform.position = (Factions.Spawn[(int)Side] + new V3(0f, 1f, 0f)).ToUnity();
            // Капсула-заглушка — отдельным телом: у примитива центр посередине, а
            // коллайдер персонажа (CharacterController) стоит от ног вверх.
            var body = GameObject.CreatePrimitive(PrimitiveType.Capsule);
            body.name = "Тело";
            var capsule = body.GetComponent<CapsuleCollider>();
            if (capsule != null) Destroy(capsule);
            body.transform.SetParent(root.transform, false);
            body.transform.localPosition = new Vector3(0f, 0.9f, 0f);
            body.transform.localScale = new Vector3(0.7f, 0.9f, 0.7f);
            var view = body.GetComponent<MeshRenderer>();
            if (view != null) view.sharedMaterial = Palette.Of("accent");
            Player = root.AddComponent<PlayerCharacter>();
            Player.Side = Side;

            var eye = new GameObject("Камера");
            eye.tag = "MainCamera";
            Rig = eye.AddComponent<CameraRig>();
            Rig.Target = Player;
        }

        static void Light()
        {
            if (Object.FindFirstObjectByType<Light>() != null) return;
            var sun = new GameObject("Солнце").AddComponent<Light>();
            sun.type = LightType.Directional;
            sun.intensity = 1.1f;
            sun.shadows = LightShadows.Soft;
            sun.transform.rotation = Quaternion.Euler(50f, -30f, 0f);
        }
    }
}
