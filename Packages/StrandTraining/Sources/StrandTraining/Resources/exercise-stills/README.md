# exercise-stills

Baked row thumbnails, one `{catalogId}.jpg` per exercise that has media.

FER-923 migrated the catalog to free-exercise-db, which ships **no media**, so the old
ExerciseDB stills were removed. Cénit's own per-exercise art (keyed by the new catalog ids)
lands here in FER-919. Until then this directory ships empty (this README keeps it present so
the `.copy("Resources/exercise-stills")` package resource and `ExerciseCatalog.stillURL` lookup
resolve — a missing still simply yields `nil`, i.e. no media).
