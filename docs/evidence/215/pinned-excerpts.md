# 고정 archive 재실측의 원본 발췌

원본의 1-based 줄 번호를 기록했다. 경로는 별칭으로 바꿨다.
원본 전체 bytes의 SHA256은 `pinned-provenance.json`에 있다.
공개 발췌는 원본 전체 로그나 원본 bytes와 동일하지 않다.

## state/build-todo-v1/output.log

```text
7: RUNSTIR215_PINNED_TOOLCHAIN compileSdk=35 buildTools=34.0.0 agp=Android Gradle Plugin version 8.7.3 gradle=8.11.1 javaHome=${JDK17_HOME} javaVersion=17.0.19 javaRuntime=17.0.19+10-LTS javaVendor=Azul Systems, Inc. arch=aarch64
81: BUILD SUCCESSFUL in 24s
82: 43 actionable tasks: 43 executed
```

## state/build-nia-v1/output.log

```text
76: RUNSTIR215_PINNED_TOOLCHAIN compileSdk=36 buildTools=36.0.0 agp=Android Gradle Plugin version 9.3.2 gradle=9.7.1 javaHome=${JDK21_HOME} javaVersion=21.0.12.1 javaRuntime=21.0.12.1+1-LTS javaVendor=Azul Systems, Inc. arch=aarch64
877: BUILD SUCCESSFUL in 13s
878: 551 actionable tasks: 235 executed, 316 from cache
```

## state/emulator-manager-v1/adb-server.log

```text
1: 10-16 09:21:58.991 69669 27130932 F adb     : main.cpp:168 could not install *smartsocket* listener: listening on specified hostname currently unsupported
```

## state/todo-focus-supplement-v1.json

```text
5:     "mCurrentFocus=Window{a6e2d90 u0 com.example.android.architecture.blueprints.main/com.example.android.architecture.blueprints.todoapp.TodoActivity}",
6:     "mFocusedApp=ActivityRecord{9155071 u0 com.example.android.architecture.blueprints.main/com.example.android.architecture.blueprints.todoapp.TodoActivity t8}",
7:     "topResumedActivity=ActivityRecord{9155071 u0 com.example.android.architecture.blueprints.main/com.example.android.architecture.blueprints.todoapp.TodoActivity t8}",
8:     "mCurrentFocus=Window{a6e2d90 u0 com.example.android.architecture.blueprints.main/com.example.android.architecture.blueprints.todoapp.TodoActivity}",
9:     "mFocusedApp=ActivityRecord{9155071 u0 com.example.android.architecture.blueprints.main/com.example.android.architecture.blueprints.todoapp.TodoActivity t8}"
```

## state/nia-post-prompt-observation-v1.json

```text
40:     "mCurrentFocus=Window{c1f0868 u0 com.google.samples.apps.nowinandroid.demo.debug/com.google.samples.apps.nowinandroid.MainActivity}",
41:     "mFocusedApp=ActivityRecord{33e0d62 u0 com.google.samples.apps.nowinandroid.demo.debug/com.google.samples.apps.nowinandroid.MainActivity t9}"
43:   "notificationChoice": "Dontallow via observedUI",
```

## state/emulator-manager-v2/emulator-final.json

```text
4:   "exitCode": 0,
```

## state/emulator-manager-v2/adb-final.json

```text
4:   "exitCode": 0,
```
