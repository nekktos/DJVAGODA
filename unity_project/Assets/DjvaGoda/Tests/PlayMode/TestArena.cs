// Общее для проверок боя: ровная площадка в настоящей сцене и боец без
// управления (бой и заклинания — как у хоста, без сети).
using System.Collections;
using DjvaGoda.Core;
using DjvaGoda.Game;
using UnityEngine;
using UnityEngine.SceneManagement;

namespace DjvaGoda.Tests
{
    public static class TestArena
    {
        /// Ровное место — дорога от тракта к деревням людей, вне леса и вдали
        /// от построек.
        public static readonly Vector3 Centre = new Vector3(-380f, 0f, -150f);

        public static IEnumerator Load()
        {
            SceneManager.LoadScene("Main");
            yield return null;
        }

        public static IEnumerator Clear()
        {
            foreach (var root in Object.FindObjectsByType<Transform>(FindObjectsSortMode.None))
                if (root != null && root.parent == null) Object.Destroy(root.gameObject);
            yield return null;
        }

        public static Vector3 Ground(Vector3 at)
        {
            RaycastHit hit;
            if (Physics.Raycast(at + Vector3.up * 50f, Vector3.down, out hit, 100f, HitZone.WorldMask, QueryTriggerInteraction.Ignore))
                return hit.point;
            return at;
        }

        public static PlayerCharacter Fighter(Faction side, Vector3 at, float yaw)
        {
            var root = new GameObject("Боец " + side);
            root.transform.position = Ground(at) + Vector3.up * 0.05f;
            Bootstrap.AddBody(root.transform, side);
            var character = root.AddComponent<PlayerCharacter>();
            character.Faction = side;
            character.LocalControl = false;
            character.Yaw = yaw;
            root.transform.rotation = CoreSpace.YawToRotation(yaw);
            root.AddComponent<PlayerCombat>();
            root.AddComponent<PlayerSpells>();
            root.AddComponent<WeaponView>();
            root.AddComponent<Builder>();
            root.AddComponent<Shop>();
            return character;
        }

        public static IEnumerator Settle()
        {
            yield return null;
            yield return new WaitForFixedUpdate();
            yield return null;
        }

        public static IEnumerator Wait(float seconds)
        {
            float t = 0f;
            while (t < seconds)
            {
                t += Time.deltaTime;
                yield return null;
            }
        }
    }
}
