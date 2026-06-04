# Literki rysowane przez dzieci 🖍️

Tu wrzucamy sprite'y literek. Z nich `LetterLabel` (skrypt `letter_label.gd`)
składa napisy w grze.

## Nazewnictwo plików — WAŻNE

```
<kod>_<numer wariantu>.png        np. a_1.png, a_2.png, b_1.png
```

- **PNG z przezroczystym tłem**, przycięte do samej literki (bez marginesów).
- Wysokość dowolna — generator i tak skaluje do zadanej wysokości napisu.
- Każda literka może mieć **dowolnie wiele wariantów**: `a_1.png`, `a_2.png`, `a_3.png`...
- Małe litery w nazwach. Cyfry też działają: `0_1.png` ... `9_1.png`.

## Polskie znaki — wspólny przyrostek `_pol`

| kod w nazwie pliku | znak |
|---|---|
| `a_pol` | ą |
| `c_pol` | ć |
| `e_pol` | ę |
| `l_pol` | ł |
| `n_pol` | ń |
| `o_pol` | ó |
| `s_pol` | ś |
| `z_pol` | ż |
| `zi_pol` | ź |

Czyli np. drugi wariant "ż" = `z_pol_2.png`. **Nie używamy ą, ć itd. w nazwach plików!**

## Znaki specjalne

| kod w nazwie pliku | znak |
|---|---|
| `pytajnik` | ? |
| `wykrzyknik` | ! |

(Windows nie pozwala na `?` w nazwie pliku, stąd kod słowny. Kolejne znaki
specjalne dodajemy analogicznie: wpis w `CODE_TO_CHAR` w `letter_label.gd`
+ pliki `<kod>_<n>.png`.)

## Jak użyć w grze

Dodaj węzeł `Node2D`, podepnij skrypt `letter_label.gd` (albo wyszukaj typ
`LetterLabel` przy dodawaniu węzła) i ustaw w inspektorze:

- `text` — treść napisu (spacje działają, wielkość liter bez znaczenia)
- `letter_height` — wysokość literek w pikselach
- `variant_mode` — `RANDOM` (losowy wariant na starcie) albo `CYCLE` (warianty
  podmieniają się w trakcie gry)
- `cycle_interval` — co ile sekund podmiana (tylko CYCLE)

Demo: scena `letters/letter_demo.tscn` (otwórz i odpal F6).

## Placeholdery

Obecne literki to **tymczasowe placeholdery** wygenerowane skryptem
`tools/generate_placeholder_letters.ps1`. Podmieniajcie je na skany rysunków
dzieci, zachowując nazewnictwo. Pamiętajcie o commitowaniu plików `.import`
razem z PNG-ami!
