# Historial de cambios

Todas las versiones de **Estruc-TI** (antes *MARCOS 2D*).

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
