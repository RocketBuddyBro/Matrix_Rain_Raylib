#include "raylib.h"
#include <math.h>
#include <stdbool.h>
#include <time.h>

#define SCREEN_WIDTH 1200
#define SCREEN_HEIGHT 760

#define CELL_SIZE 18
#define MAX_COLUMNS 300
#define MAX_TRAIL 24

typedef struct RainColumn {
    float headY;
    float speed;
    int trailLength;
    char glyphs[MAX_TRAIL];
} RainColumn;

static RainColumn columns[MAX_COLUMNS];
static bool paused = false;
static bool firstFrame = true;

/* Return a random letter, number, or symbol. */
static char RandomGlyph(void)
{
    int type = GetRandomValue(0, 9);

    if (type < 4)
        return (char)GetRandomValue('A', 'Z');

    if (type < 7)
        return (char)GetRandomValue('0', '9');

    if (type < 9)
        return (char)GetRandomValue('a', 'z');

    const char symbols[] = "@#$%&*+-=<>";
    return symbols[GetRandomValue(0, 10)];
}

/* Give every stream its own position, speed, and trail. */
static void InitializeRain(void)
{
    for (int i = 0; i < MAX_COLUMNS; i++) {
        columns[i].headY =
            (float)GetRandomValue(-SCREEN_HEIGHT, SCREEN_HEIGHT);

        columns[i].speed =
            (float)GetRandomValue(90, 260);

        columns[i].trailLength =
            GetRandomValue(8, MAX_TRAIL);

        for (int j = 0; j < MAX_TRAIL; j++) {
            columns[i].glyphs[j] = RandomGlyph();
        }
    }
}

/* Move the streams and occasionally change their characters. */
static void UpdateRain(float deltaTime)
{
    int screenHeight = GetScreenHeight();

    for (int i = 0; i < MAX_COLUMNS; i++) {
        RainColumn *column = &columns[i];

        column->headY += column->speed * deltaTime;

        /* Restart a stream after its entire trail leaves the screen. */
        if (column->headY -
                column->trailLength * CELL_SIZE > screenHeight) {
            column->headY =
                (float)-GetRandomValue(0, screenHeight / 2);

            column->speed =
                (float)GetRandomValue(90, 260);

            column->trailLength =
                GetRandomValue(8, MAX_TRAIL);
        }

        /* Randomly update existing glyphs. */
        for (int j = 0; j < column->trailLength; j++) {
            if (GetRandomValue(0, 100) < 3) {
                column->glyphs[j] = RandomGlyph();
            }
        }
    }
}

/* Draw the characters and their fading green trails. */
static void DrawRain(void)
{
    int screenWidth = GetScreenWidth();
    int screenHeight = GetScreenHeight();

    int visibleColumns =
        (screenWidth + CELL_SIZE - 1) / CELL_SIZE;

    if (visibleColumns > MAX_COLUMNS)
        visibleColumns = MAX_COLUMNS;

    for (int i = 0; i < visibleColumns; i++) {
        RainColumn *column = &columns[i];

        int headRow =
            (int)floorf(column->headY / CELL_SIZE);

        for (int j = 0; j < column->trailLength; j++) {
            int row = headRow - j;
            int y = row * CELL_SIZE;

            if (row < 0 || y >= screenHeight)
                continue;

            float brightness =
                1.0f - (float)j / column->trailLength;

            Color color = {
                (unsigned char)(5 + 15 * brightness),
                (unsigned char)(35 + 205 * brightness),
                (unsigned char)(8 + 30 * brightness),
                255
            };

            /* The leading character is brighter than the trail. */
            if (j == 0) {
                color = (Color){ 210, 255, 220, 255 };
            }

            char text[2] = {
                column->glyphs[j],
                '\0'
            };

            DrawText(
                text,
                i * CELL_SIZE,
                y,
                CELL_SIZE,
                color
            );
        }
    }
}

int main(void)
{
    SetConfigFlags(FLAG_WINDOW_RESIZABLE);

    InitWindow(
        SCREEN_WIDTH,
        SCREEN_HEIGHT,
        "Matrix Rain - C and raylib"
    );

    SetWindowMinSize(640, 400);
    SetTargetFPS(60);

    SetRandomSeed((unsigned int)time(NULL));
    InitializeRain();

    while (!WindowShouldClose()) {
        float deltaTime = GetFrameTime();

        /* Prevent a large movement jump after restoring the window. */
        if (deltaTime > 0.05f)
            deltaTime = 0.05f;

        if (IsKeyPressed(KEY_SPACE))
            paused = !paused;

        if (IsKeyPressed(KEY_F11))
            ToggleFullscreen();

        if (!paused)
            UpdateRain(deltaTime);

        BeginDrawing();

        if (firstFrame) {
            ClearBackground(BLACK);
            firstFrame = false;
        } else if (!paused) {
            /*
             * A transparent black overlay gradually fades
             * characters drawn during previous frames.
             */
            DrawRectangle(
                0, 0,
                GetScreenWidth(),
                GetScreenHeight(),
                (Color){ 0, 0, 0, 12 }
            );
        }

        DrawRain();

        if (paused) {
            DrawText(
                "PAUSED - PRESS SPACE TO RESUME",
                18, 18, 18, GREEN
            );
        }

        EndDrawing();
    }

    CloseWindow();
    return 0;
}
