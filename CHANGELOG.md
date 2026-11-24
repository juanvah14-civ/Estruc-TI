# Historial de cambios

Todas las versiones de **Estruc-TI** (antes *MARCOS 2D*).

## [1.3] — 2026-11

### Agregado
- **Editor gráfico** (*Modelo → Editor gráfico*, o `enter` en *Ver modelo*): un cursor se mueve sobre una malla de
  puntos con las flechas y `tab` cambia entre tres modos:
  - **Nudos**: `enter` crea un nudo en el punto del cursor o edita el nudo existente; `a` cambia el apoyo; `del` lo borra.
  - **Barras**: `enter` en un nudo inicia la barra y `enter` en otro la termina; se puede seguir encadenando barras
    (`esc` termina). `t` alterna entre **marco** y **armadura** (rótulas en ambos extremos). Las barras se orientan
    solas: vigas de izquierda a derecha y columnas de abajo hacia arriba. Avisa si la barra ya existe.
  - **Cargas**: `enter` sobre un nudo crea una carga en el nudo; sobre una barra, una carga puntual a la distancia del
    cursor (se puede cambiar a distribuida). Si ya hay cargas, permite editarlas; `del` las borra.
  - `g` cambia el paso de la malla (por defecto 1 m, 100 cm, 1000 mm, 1 ft o 12 in).
- **Vista previa en las listas** de nudos, elementos y cargas: la mitad superior dibuja el modelo y resalta en rojo el
  registro seleccionado. `v` la muestra u oculta y `g` abre el editor gráfico.
- Nuevo ejemplo «Armadura con carga P».

### Mejorado
- **Diagramas legibles**: los valores ya no se enciman; si un lugar está ocupado se busca otro, los valores repetidos
  en un mismo nudo se escriben una sola vez y cada valor tiene fondo blanco sobre el rayado.
- **Tablas**: el ancho de cada columna se ajusta a su contenido (letra 9 o 7). Si no caben todas, la primera columna
  queda fija y las demás se recorren con izquierda/derecha.
- **Resumen de RESOLVER**: los valores largos pasan a su propia línea.
- Pruebas automáticas: de 105 a **132** comprobaciones.

## [1.2] — 2026-11

### Agregado
- **Cargas incógnitas.** En el valor de cualquier carga (en nudos o en elementos) se puede escribir una expresión
  lineal con letras: `P`, `-2P`, `P/2`, `w`, `3+0.5w`, `2(P+1)`... Se aceptan varias incógnitas a la vez.
- Reacciones, desplazamientos de nudos, fuerzas en extremos y **ecuaciones por tramo** se muestran **en función de
  las incógnitas** (por ejemplo `Ry1 = 30 + 0.66667P`). Se obtienen por superposición, sin aproximaciones.
- **Modelo → Incógnitas (P, w...)**: valores de prueba de cada incógnita (por defecto 1). Los diagramas, la deformada
  y la tabla de máximos se calculan con esos valores.
- **Solución → Despejar incógnita**: calcula el valor de una incógnita para que una reacción, un desplazamiento de
  nudo o un esfuerzo N, V, M, θ, δ en un punto *x* tome el valor deseado (por ejemplo, ¿qué P da Ry1 = 40 kN?).
  El resultado se puede usar como nuevo valor de prueba.
- Vista por elemento: tecla **`s`** para ver N, V, M, θ, δ, u, Δx y Δy del punto en función de las incógnitas.
- Nuevo ejemplo «Viga con carga P (incógnita)»: viga simple con carga puntual `-P` y carga distribuida.

### Cambiado
- La app se presenta como **Estruc-TI** (antes *MARCOS 2D*) en el inicio y en *Acerca de*.
- Las cargas con incógnitas se dibujan con su valor de prueba y se rotulan con su expresión (`-P`, `2w`...).
- Pruebas automáticas: de 72 a **105** comprobaciones (lectura de expresiones, superposición en vigas y marcos
  hiperestáticos, ecuaciones simbólicas, despeje, unidades y guardado).

## [1.1] — 2026-11

### Agregado
- Nueva interfaz de menús y formularios.
- **Ecuaciones por tramo** de los esfuerzos de cada elemento (`e` desde la vista de diagramas o *Resultados → Ecuaciones por tramo*).

## [1.0] — 2026-11

### Primera versión
- Método directo de rigidez con 3 GDL por nudo para vigas, marcos y armaduras planas.
- Apoyos: libre, empotrado, articulado, rodillos X/Y, deslizaderas X/Y; rótulas, asentamientos y resortes.
- Cargas en nudos y en barras: puntuales, momentos, distribuidas uniformes, triangulares y trapezoidales (parciales), con direcciones global, local y proyectada.
- Seis unidades de fuerza y cinco de longitud con conversión del modelo.
- Clasificación isostática / hiperestática / inestable.
- Reacciones, desplazamientos, fuerzas en extremos, tabla de máximos y diagramas N, V, M, θ, δ y deformada.
- Vista por elemento con cursor y consulta en una *x* exacta.
- Cinco ejemplos incluidos y manual de usuario en PDF.
