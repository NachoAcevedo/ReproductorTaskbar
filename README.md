# Reproductor Taskbar

Widget de música para la taskbar de Windows: muestra la canción, el artista y la carátula, con controles de reproducción.

## Qué hace

- Se incrusta dentro de la taskbar, abajo a la izquierda, y se ajusta a su alto y a la escala de pantalla.
- Muestra título, artista, álbum y carátula del reproductor activo (Spotify, navegador, Windows Media Player y cualquier app que publique su música a Windows).
- Botones de anterior, reproducir / pausar y siguiente, enviados directamente al reproductor activo.
- Se actualiza solo por eventos de Windows, sin consultas periódicas; la carátula se decodifica una vez por canción.
- Si se reinicia Explorer, vuelve a aparecer solo.
- Ícono en la bandeja del sistema con:
  - **Carátula**: mostrarla u ocultarla (se recuerda entre reinicios).
  - **Iniciar con Windows**.
  - **Salir**.

## Requisitos

- Windows 10 (2004) o Windows 11.
- [.NET 8 Desktop Runtime](https://dotnet.microsoft.com/download/dotnet/8.0).

## Compilar

```powershell
dotnet publish ReproductorTaskbar\ReproductorTaskbar.csproj -c Release -o publish
```

Genera `publish\ReproductorTaskbar.exe`. Doble click para ejecutarlo.

## Versión anterior

La versión original en PowerShell está en la rama [`old`](../../tree/old).

## Licencia

GPL-3.0. Ver [LICENSE](LICENSE).
