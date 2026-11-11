#include <IOKit/IOKitLib.h>
#include <stdint.h>
#include <stdio.h>
#include <string.h>

typedef struct {
    uint32_t dataSize;
    uint32_t dataType;
    uint8_t dataAttributes;
} SMCKeyInfo;

typedef struct {
    uint8_t major, minor, build, reserved;
    uint16_t release;
} SMCVersion;

typedef struct {
    uint16_t version, length;
    uint32_t cpuLimit, gpuLimit, memoryLimit;
} SMCPowerLimit;

typedef struct {
    uint32_t key;
    SMCVersion version;
    SMCPowerLimit powerLimit;
    SMCKeyInfo keyInfo;
    uint8_t result;
    uint8_t status;
    uint8_t command;
    uint32_t data32;
    uint8_t bytes[32];
} SMCKeyData;

static uint32_t fourcc(const char key[4]) {
    return ((uint32_t)(uint8_t)key[0] << 24) | ((uint32_t)(uint8_t)key[1] << 16) |
           ((uint32_t)(uint8_t)key[2] << 8) | (uint8_t)key[3];
}

static kern_return_t callSMC(io_connect_t connection, SMCKeyData *input, SMCKeyData *output) {
    size_t outputSize = sizeof(*output);
    memset(output, 0, sizeof(*output));
    kern_return_t result = IOConnectCallStructMethod(connection, 2, input, sizeof(*input), output, &outputSize);
    return result;
}

static int readTemperature(io_connect_t connection, const char key[5], double *temperature) {
    SMCKeyData input = {0}, output;
    input.key = fourcc(key);
    input.command = 9; /* Read key info */
    kern_return_t keyResult = callSMC(connection, &input, &output);
    if (keyResult != KERN_SUCCESS || output.keyInfo.dataSize < 2 || output.keyInfo.dataSize > 32) {
        return 0;
    }

    uint32_t size = output.keyInfo.dataSize;
    input = (SMCKeyData){0};
    input.key = fourcc(key);
    input.keyInfo.dataSize = size;
    input.command = 5; /* Read bytes */
    if (callSMC(connection, &input, &output) != KERN_SUCCESS)
        return 0;

    int16_t fixed = (int16_t)(((uint16_t)output.bytes[0] << 8) | output.bytes[1]);
    double value = (double)fixed / 256.0; /* SMC temperature keys use signed sp78 */
    if (value < -10.0 || value > 125.0)
        return 0;
    *temperature = value;
    return 1;
}

int main(void) {
    static const char *keys[] = {"TC0P", "TC0D", "TC0F", "TC0H", "TCAH", "TCBH", "TC0C", "TC0E", "TC0G", "TCXC"};
    io_service_t service = IOServiceGetMatchingService(kIOMainPortDefault, IOServiceMatching("AppleSMC"));
    if (!service) {
        puts("CPU temperature unavailable: AppleSMC service not found");
        return 1;
    }

    io_connect_t connection = IO_OBJECT_NULL;
    kern_return_t result = IOServiceOpen(service, mach_task_self(), 0, &connection);
    IOObjectRelease(service);
    if (result != KERN_SUCCESS) {
        puts("CPU temperature unavailable: AppleSMC could not be opened");
        return 1;
    }

    double temperature = 0;
    int found = 0;
    for (size_t i = 0; i < sizeof(keys) / sizeof(keys[0]); ++i) {
        if (readTemperature(connection, keys[i], &temperature)) {
            found = 1;
            break;
        }
    }
    IOServiceClose(connection);
    if (!found) {
        puts("CPU temperature unavailable: no CPU sensor key in SMC");
        return 1;
    }

    printf("CPU die temperature: %.1f C\n", temperature);
    return 0;
}
