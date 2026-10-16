# flutter_local_notifications хранит расписание через Gson с дженериками —
# без этих правил R8 ломает запланированные уведомления в release-сборке.
-keep class com.dexterous.** { *; }
-keepattributes Signature
-keepattributes *Annotation*
-keep class com.google.gson.reflect.TypeToken { *; }
-keep class * extends com.google.gson.reflect.TypeToken
