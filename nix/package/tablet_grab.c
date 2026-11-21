#include <errno.h>
#include <fcntl.h>
#include <linux/input.h>
#include <poll.h>
#include <signal.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/ioctl.h>
#include <sys/prctl.h>
#include <time.h>
#include <unistd.h>

#define PID_FILE "/data/local/tmp/pangu-tablet-grab.pid"
#define HEARTBEAT_NS (2000000000LL)
#define MUX_TAG_PEN ((unsigned char)0)
#define MUX_TAG_TOUCH ((unsigned char)1)
#define MUX_TAG_HEARTBEAT ((unsigned char)255)

static volatile sig_atomic_t stop_flag = 0;

static void on_signal(int sig) {
    (void)sig;
    stop_flag = 1;
}

static long long now_ns(void) {
    struct timespec ts;
    clock_gettime(CLOCK_MONOTONIC, &ts);
    return (long long)ts.tv_sec * 1000000000LL + ts.tv_nsec;
}

static int is_grab_pid(pid_t pid) {
    if (pid <= 1 || pid == getpid()) return 0;
    char path[64];
    char comm[64];
    snprintf(path, sizeof(path), "/proc/%ld/comm", (long)pid);
    FILE *f = fopen(path, "r");
    if (!f) return 0;
    size_t r = fread(comm, 1, sizeof(comm) - 1, f);
    fclose(f);
    comm[r] = '\0';
    return strncmp(comm, "pangu-tablet", 12) == 0;
}

static void replace_previous_instance(void) {
    FILE *f = fopen(PID_FILE, "r");
    if (f) {
        long prev = 0;
        if (fscanf(f, "%ld", &prev) == 1 && prev > 1) {
            pid_t pid = (pid_t)prev;
            if (is_grab_pid(pid)) {
                kill(pid, SIGTERM);
                for (int i = 0; i < 25; i++) {
                    if (kill(pid, 0) != 0) break;
                    usleep(10000);
                }
                if (is_grab_pid(pid)) kill(pid, SIGKILL);
            }
        }
        fclose(f);
    }
    FILE *out = fopen(PID_FILE, "w");
    if (out) {
        fprintf(out, "%ld\n", (long)getpid());
        fclose(out);
    }
}

static void cleanup_pid_file(void) {
    FILE *f = fopen(PID_FILE, "r");
    if (!f) return;
    long cur = 0;
    int match = (fscanf(f, "%ld", &cur) == 1 && (pid_t)cur == getpid());
    fclose(f);
    if (match) unlink(PID_FILE);
}

static int write_all(int fd, const char *buf, size_t len) {
    size_t off = 0;
    while (off < len) {
        ssize_t w = write(fd, buf + off, len - off);
        if (w < 0) {
            if (errno == EINTR) continue;
            return -1;
        }
        off += (size_t)w;
    }
    return 0;
}

static int write_mux_events(unsigned char tag, const struct input_event *evs, size_t count) {
    const size_t ev_sz = sizeof(struct input_event);
    const size_t frame_sz = 1 + ev_sz;
    unsigned char out[64 * (1 + sizeof(struct input_event))];
    size_t idx = 0;
    while (idx < count) {
        size_t chunk = count - idx;
        if (chunk > 64) chunk = 64;
        for (size_t i = 0; i < chunk; i++) {
            out[i * frame_sz] = tag;
            memcpy(&out[i * frame_sz + 1], &evs[idx + i], ev_sz);
        }
        if (write_all(STDOUT_FILENO, (const char *)out, chunk * frame_sz) < 0) return -1;
        idx += chunk;
    }
    return 0;
}

// Usage:
//   tablet-grab <pen_evdev> <grab_pen:0|1> [extra_grab_evdev...]
//   tablet-grab --mux <pen_evdev|-> <grab_pen:0|1> <touch_evdev|-> <grab_touch:0|1>
int main(int argc, char **argv) {
    if (argc < 3) return 2;

    prctl(PR_SET_PDEATHSIG, SIGTERM);
    signal(SIGHUP, on_signal);
    signal(SIGINT, on_signal);
    signal(SIGTERM, on_signal);
    signal(SIGPIPE, SIG_IGN);

    replace_previous_instance();

    int mux_mode = strcmp(argv[1], "--mux") == 0;
    int fds[8];
    int grabbed[8];
    int forward[8];
    unsigned char tags[8];
    int n = 0;

    if (mux_mode) {
        if (argc < 6) {
            cleanup_pid_file();
            return 2;
        }
        const char *pen_path = argv[2];
        int grab_pen = atoi(argv[3]) != 0;
        const char *touch_path = argv[4];
        int grab_touch = atoi(argv[5]) != 0;

        if (strcmp(pen_path, "-") != 0) {
            int fd = open(pen_path, O_RDONLY | O_NONBLOCK);
            if (fd >= 0) {
                fds[n] = fd;
                grabbed[n] = (grab_pen && ioctl(fd, EVIOCGRAB, 1) == 0) ? 1 : 0;
                forward[n] = 1;
                tags[n] = MUX_TAG_PEN;
                n++;
            }
        }
        if (strcmp(touch_path, "-") != 0) {
            int fd = open(touch_path, O_RDONLY | O_NONBLOCK);
            if (fd >= 0) {
                fds[n] = fd;
                grabbed[n] = (grab_touch && ioctl(fd, EVIOCGRAB, 1) == 0) ? 1 : 0;
                forward[n] = 1;
                tags[n] = MUX_TAG_TOUCH;
                n++;
            }
        }
        if (n == 0) {
            cleanup_pid_file();
            return 1;
        }
    } else {
        int grab_pen = atoi(argv[2]) != 0;
        int pen_fd = open(argv[1], O_RDONLY | O_NONBLOCK);
        if (pen_fd < 0) {
            cleanup_pid_file();
            return 1;
        }
        fds[n] = pen_fd;
        grabbed[n] = (grab_pen && ioctl(pen_fd, EVIOCGRAB, 1) == 0) ? 1 : 0;
        forward[n] = 1;
        tags[n] = MUX_TAG_PEN;
        n++;

        for (int i = 3; i < argc && n < 8; i++) {
            int fd = open(argv[i], O_RDONLY | O_NONBLOCK);
            if (fd < 0) continue;
            if (ioctl(fd, EVIOCGRAB, 1) == 0) {
                fds[n] = fd;
                grabbed[n] = 1;
                forward[n] = 0;
                tags[n] = MUX_TAG_TOUCH;
                n++;
            } else {
                close(fd);
            }
        }
    }

    struct pollfd pfds[9];
    struct input_event evs[64];
    struct input_event hb;
    memset(&hb, 0, sizeof(hb));
    hb.type = EV_SYN;
    hb.code = 0xFFFF; // Ignored by tablet_bridge.py; forces adbd to detect dead Wi-Fi/host sockets.
    long long last_write = now_ns();

    while (!stop_flag) {
        int active_forward = 0;
        pfds[0].fd = STDOUT_FILENO;
        pfds[0].events = 0;
        pfds[0].revents = 0;
        for (int i = 0; i < n; i++) {
            pfds[i + 1].fd = fds[i];
            pfds[i + 1].events = POLLIN;
            pfds[i + 1].revents = 0;
            if (fds[i] >= 0 && forward[i]) active_forward++;
        }
        if (active_forward == 0) break;

        int rc = poll(pfds, (nfds_t)(n + 1), 250);
        if (rc < 0) {
            if (errno == EINTR) continue;
            break;
        }
        if (pfds[0].revents & (POLLERR | POLLHUP | POLLNVAL)) break;

        if (rc == 0) {
            long long now = now_ns();
            if (now - last_write >= HEARTBEAT_NS) {
                int wrc = mux_mode
                    ? write_mux_events(MUX_TAG_HEARTBEAT, &hb, 1)
                    : write_all(STDOUT_FILENO, (const char *)&hb, sizeof(hb));
                if (wrc < 0) break;
                last_write = now;
            }
            continue;
        }

        for (int i = 0; i < n && !stop_flag; i++) {
            if (fds[i] < 0) continue;
            short rev = pfds[i + 1].revents;
            if (rev & (POLLERR | POLLHUP | POLLNVAL)) {
                if (grabbed[i]) ioctl(fds[i], EVIOCGRAB, 0);
                close(fds[i]);
                fds[i] = -1;
                grabbed[i] = 0;
                if (!mux_mode && i == 0) stop_flag = 1;
                continue;
            }
            if (!(rev & POLLIN)) continue;

            for (;;) {
                ssize_t r = read(fds[i], evs, sizeof(evs));
                if (r > 0) {
                    if (forward[i]) {
                        int wrc;
                        if (mux_mode) {
                            size_t count = (size_t)r / sizeof(struct input_event);
                            wrc = write_mux_events(tags[i], evs, count);
                        } else {
                            wrc = write_all(STDOUT_FILENO, (const char *)evs, (size_t)r);
                        }
                        if (wrc < 0) {
                            stop_flag = 1;
                            break;
                        }
                        last_write = now_ns();
                    }
                } else if (r < 0 && (errno == EAGAIN || errno == EWOULDBLOCK)) {
                    break;
                } else {
                    if (grabbed[i]) ioctl(fds[i], EVIOCGRAB, 0);
                    close(fds[i]);
                    fds[i] = -1;
                    grabbed[i] = 0;
                    if (!mux_mode && i == 0) stop_flag = 1;
                    break;
                }
            }
        }
    }

    for (int i = 0; i < n; i++) {
        if (fds[i] < 0) continue;
        if (grabbed[i]) ioctl(fds[i], EVIOCGRAB, 0);
        close(fds[i]);
    }
    cleanup_pid_file();
    return 0;
}
