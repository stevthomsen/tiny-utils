#include <sys/socket.h>
#include <sys/types.h>
#include <netinet/in.h>
#include <netdb.h>
#include <stdio.h>
#include <string.h>
#include <stdlib.h>
#include <unistd.h>
#include <errno.h>
#include <arpa/inet.h> 
#include <sys/stat.h>
#include <fcntl.h>
#include <signal.h>

#define NAME_MAX_LENGTH 300

#define HELP "\n Usage: %s <ip_addr> {output file}\n\n" \
             "  ip_addr            IP Address of tracestore server.\n" \
             "  {output file}      If not specified, will use `cwd`/trace_data.dat\n\n" \
             "    1. Run trace_client <ip_addr>\n" \
             "    2. Send command: udws \"trace_store.set_trace_mask 1835 1\"\n" \
             "    3. Send command: udws \"trace_store.set_trace_mask 1835 0\"\n" \
             "    4. trace_client will exit after server closes connection.\n"

struct sigaction act;
static int terminate = 0;

static void sighandler (int signum, siginfo_t *info, void *ptr)
{
    printf("\n received signal %d! \n", signum);
    terminate = 1;
}

int main(int argc, char *argv[])
{
    int sockfd = 0, n = 0, r = 0;
    char recvBuff[1024];
    struct sockaddr_in serv_addr; 
    char fs_path[NAME_MAX_LENGTH];
    int fd = -1;
    char cwd[NAME_MAX_LENGTH];
    char *default_filename = "/trace_data.dat";

    if(argc < 2)
    {
        printf(HELP,argv[0]);
        return 1;
    }

    if(argc < 3)
    {
        if((getcwd(cwd, sizeof(cwd)) == NULL) || \
           (strncat(cwd, default_filename, sizeof(cwd)-(strlen(cwd)+1)) == NULL))
        {
            printf("\n Error : Could not formulate default output path\n");
            return 1;
        }
    }
    else
    {
        strncpy(cwd, argv[2], sizeof(cwd));
    }

    memset(recvBuff, '0',sizeof(recvBuff));
    if((sockfd = socket(AF_INET, SOCK_STREAM, 0)) < 0)
    {
        printf("\n Error : Could not create socket \n");
        return 1;
    } 
    
    act.sa_sigaction = sighandler;
    act.sa_flags = SA_SIGINFO;

    sigaction(SIGINT, &act, NULL);
    sigaction(SIGTERM, &act, NULL);

    memset(&serv_addr, '0', sizeof(serv_addr)); 

    serv_addr.sin_family = AF_INET;
    serv_addr.sin_port = htons(2728); 

    if(inet_pton(AF_INET, argv[1], &serv_addr.sin_addr)<=0)
    {
        printf("\n inet_pton error occured\n");
        return 1;
    } 

    if( connect(sockfd, (struct sockaddr *)&serv_addr, sizeof(serv_addr)) < 0)
    {
       printf("\n Error : Connect Failed \n");
       return 1;
    } 
    sprintf(fs_path, "%s", cwd);

    fd = open(fs_path, O_CREAT|O_WRONLY|O_TRUNC, S_IRWXU | S_IRWXG | S_IRWXO);
    if(fd  == -1)
    {
        printf("\n Error file open failed ... %d %d\n", fd, errno);
        return 1;
    }

    printf("\n waiting for data ... %d \n", fd );
   
    while(!terminate)
    {
        if ( (n = read(sockfd, recvBuff, sizeof(recvBuff)-1)) > 0)
        {
            //printf("\n received %d, %s\n", n, recvBuff);
            recvBuff[n] = 0;
            r = write(fd, recvBuff, n);
            if(r > 0)
            {
                //printf("\n write\n");
            }
            else
            {
                printf("\n Error : write error %d \n", errno);
            }

        }
        else
        {
            break;
        }
        if(terminate)
        {
            /* terminate received  */
            printf("\n terminating \n");
            break;
        }
    }
   
    if(terminate)
    {
        printf("\n closing \n");
        shutdown(sockfd, SHUT_RDWR);
        close(sockfd);
    }

    close(fd);

    return 0;
}

