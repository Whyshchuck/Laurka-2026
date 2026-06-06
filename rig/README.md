# Rigowanie ucznia — krok po kroku

Cel: sprite dziecka przypięty do szkieletu 15 kości, działający ze wspólnymi
animacjami z `pupil_anims.tres` (machanie, machanie_oba, hura, taniec,
kiwanie, uklon).

## Procedura

1. **Duplikat sceny**
   FileSystem → prawy przycisk na `rig/michal_rig.tscn` → *Duplicate* →
   nazwij `rig/<imie>_rig.tscn`. Otwórz i zmień nazwę root node'a
   (np. `WojtekRig`).

2. **Podmień teksturę**
   Zaznacz `Polygon2D` → przeciągnij sprite dziecka (z `sprites/`)
   w pole `texture` w Inspektorze.

3. **Obrysuj**
   Inspektor → przycisk **„Obrysuj sprite'a"**.
   Kontur poszarpany albo punktów za dużo/za mało → zmień `epsilon`
   (mniejszy = dokładniej) i kliknij ponownie. Wagi się nie gubią.

4. **Rozstaw kości**
   Najpierw automat: Inspektor → **„Rozstaw kości ze sprite'a"** —
   znajduje czubek głowy, dłonie (skrajne punkty), stopy i krocze,
   a łokcie/kolana stawia w połowie kończyn. Potem dociągnij w viewporcie
   te kości, które nie trafiły (zwykle 2-4: łokcie przy zgiętych rękach,
   stopy przy szerokich butach).
   **Tylko przesuwaj, nie obracaj.** „Set Rest" nie jest potrzebny —
   krok 6 sam synchronizuje.
   Założenia automatu: postać frontalna, ręce odstają od tułowia (A/T-pose),
   głowa u góry mniej więcej nad tułowiem.

5. **(Opcjonalnie) punkty wewnętrzne**
   Przycisk **UV** na pasku → tryb **Points** → narzędzie *Create Point* →
   kliknij WEWNĄTRZ kształtu (1-2 punkty na bark, po 1 na łokcie/kolana).
   Uwaga: edycja obrysu w głównym viewporcie (poza oknem UV) rozjeżdża
   uv/wagi — gdyby sprite znikł, przycisk **„Napraw UV i wagi"**.

6. **Przelicz**
   Zaznacz `Polygon2D` → przycisk **„Przelicz siatkę i wagi"**.
   Robi po kolei: rest kości = pozycje, triangulację (gdy są punkty
   wewnętrzne), auto-wagi (najbliższa kość + rozmycie na stawach,
   promień `blend_radius`).

7. **Zapisz i przetestuj**
   Ctrl+S → zaznacz `AnimationPlayer` → odpal `machanie_oba` albo `taniec`.
   Animacje są wspólne — działają od razu, bo nazwy kości się zgadzają.

8. **(Opcjonalnie) kosmetyka**
   Ręczne poprawki pędzlem (okno UV → Bones) zawsze NA KOŃCU —
   „Przelicz siatkę i wagi" oraz „Auto-wagi" nadpisują malowanie.

## Kontrola jakości z terminala

```
godot --headless --script res://rig/check_weights.gd -- res://rig/<imie>_rig.tscn
godot --headless --script res://rig/check_arm.gd     -- res://rig/<imie>_rig.tscn
```

`check_weights`: wierzchołki bez wag + wagi-uciekinierzy nad brodą.
`check_arm`: rozkład udziału rąk (bark powinien mieć ~0.7, daleka ręka 1.0).

## Awaryjnie: pipeline bez edytora

Gdy przyciski w Inspektorze nie reagują (edytor trzyma stary skrypt):
**zamknij scenę w edytorze**, potem:

```
godot --headless --script res://rig/apply_autoweights.gd -- res://rig/<imie>_rig.tscn
```

(zapisuje scenę na dysku — dlatego musi być zamknięta).

## Na co uważać

- Ręce przy tułowiu (brak A-pose): auto-wagi mogą skleić rękę z biodrem —
  zmniejsz `blend_radius` albo popraw pędzlem.
- Dłonie/stopy skierowane inaczej niż u Michała: popraw `bone_angle`
  i `length` kości-liści (Dlon*, Stopa*, Glowa) w Inspektorze.
- Kość z rotacją ≠ 0 w spoczynku → ostrzeżenie w Output przy przeliczaniu;
  wyzeruj rotację (animacje zakładają rest = 0).
