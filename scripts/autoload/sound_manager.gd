extends Node
## Autoload Singleton: SoundManager
##
## Rol (Modulul 1): punct central unde Player raportează evenimentele de zgomot
## pe care le produce (pași, sprint, manivelă lanternă etc.).
##
## Extindere (Modulul 2): AI-ul "The Silt" se va abona la `noise_emitted`
## pentru a decide tranziția PATROL -> INVESTIGATING -> HUNTING, comparând
## distanța până la sursă cu `radius` primit aici.
##
## Înregistrare: Project Settings -> Autoload -> adaugă acest script cu
## numele "SoundManager" (deja configurat în project.godot).

## Emis de fiecare dată când în lume are loc un eveniment sonor.
## @param origin: poziția globală a sursei de zgomot.
## @param radius: raza (în metri) în care zgomotul poate fi "auzit".
## @param intensity: 0.0-1.0, cât de puternic e sunetul (folosit ca prioritate).
signal noise_emitted(origin: Vector3, radius: float, intensity: float)


func emit_noise(origin: Vector3, radius: float, intensity: float) -> void:
	noise_emitted.emit(origin, radius, intensity)
