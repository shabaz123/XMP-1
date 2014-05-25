/*
 * spi-test.xc
 *
 *  Created on: 10 May 2014
 *      Author: shabaz
 */
#include <xs1.h>
#include <xscope.h>
#include <string.h>
#include "spi_slave.h"
#include <stdio.h>

spi_slave_interface spi_sif =
{
    XS1_CLKBLK_3,
    XS1_PORT_1B, // SS
    XS1_PORT_1A, // MOSI
    XS1_PORT_1D, // MISO
    XS1_PORT_1C  // SCLK
};

// SS pin on PORT_32A is on pin P32A1, which is 0x02 bitmask
#define SS_BITMASK 0x02
#define BUFLEN 4096

port ss_port=XS1_PORT_32A;


// clock for servo handling
clock clk = XS1_CLKBLK_1;
// servo ports
out buffered port:1 servo_port[8] = {XS1_PORT_1F, XS1_PORT_1H, XS1_PORT_1G, XS1_PORT_1E,
                                     XS1_PORT_1J, XS1_PORT_1K, XS1_PORT_1M, XS1_PORT_1N};



// codes
#define OK 1
#define NOK 2
#define SEND 3

interface to_rpi
{
    void array_data(unsigned char val[BUFLEN+3]);
    void code(unsigned char c);
};

interface from_rpi
{
    unsigned char* movable array_data(unsigned char* movable bufp);
    void code(unsigned char c);
};

interface servo_data
{
    [[notification]] slave void data_ready(void);
    [[clears_notification]] unsigned int* movable get_data(unsigned int* movable servop);
};

void
spi_process(interface to_rpi server s, interface from_rpi client c)
{
    int pval;
    unsigned int len;
    unsigned char buffer_valid=0;
    unsigned char tosend=0;
    unsigned char bufa[BUFLEN+3];

    unsigned char* movable buf=bufa;

    printf("slave_init..\n");
    spi_slave_init(spi_sif);
    printf("...done\n");

    while(1)
    {
        // find state of PORT_32A
        ss_port :> pval; // get current port values
        if (pval & SS_BITMASK) // SS is high, i.e. deselected
        {
            // nothing to do
        }
        else
        {
            pval &= ~SS_BITMASK;
        }

        select
        {
            case ss_port when pinsneq(pval) :> int portval:
                if (portval & SS_BITMASK) // SS is high, i.e. deselected
                {
                    printf("high event\n");
                    // data transfer is either complete, or aborted
                    // we don't check. Leave it to any higher level
                    // protocol to figure out.
                }
                else
                {
                    // SS is low, i.e. selected
                    // do we have any data to send?
                    if (buffer_valid && tosend)
                    {
                        //printf("tx\n");
                        len=(((unsigned int)buf[1])<<8) | ((unsigned int)buf[2]);
                        spi_slave_out_buffer(spi_sif, buf, len+3);
                        buffer_valid=0;
                        tosend=0;
                        c.code(OK);
                        printf("sent\n");
                    }
                    else
                    {
                        //printf("rx\n");
                        // if we're not sending then we're receiving
                        spi_slave_in_buffer(spi_sif, buf, BUFLEN+3);
                        printf("in_buffer executed, from buf[0] is %02x, %02x, %02x, %02x, %02x, %02x\n", buf[0], buf[1], buf[2], buf[3], buf[4], buf[5]);
                        // is it an instruction for us to send data back
                        // to the RPI later?
                        if (buf[0] & 0x01) // LSB set indicates the RPI wants a response
                        {
                            tosend=1;
                        }
                        buffer_valid=0; // buffer contains data from RPI, not data valid for sending to RPI
                        buf=c.array_data(move(buf));
                        if (buf[0]==0x51)
                        {
                            printf("error!");
                        }
                        if (buf==NULL)
                        {
                            printf("Null!!!\n");
                        }
                    }
                    printf("buffer_valid=%d, tosend=%d\n", buffer_valid, tosend);
                    printf("Now from buf[0] is %02x, %02x, %02x, %02x\n", buf[0], buf[1], buf[2], buf[3]);

                }
                break;
            case s.code(unsigned char c):
                if (c==SEND)
                {
                    // ok we should send out the buffer contents to the RPI
                    buffer_valid=1;
                    printf("send here!! buffer_valid=%d, tosend=%d\n", buffer_valid, tosend);
                }
                break;
            case s.array_data(unsigned char v[BUFLEN+3]):
                // ok we have received data to send to RPI.
                // we store it, until SS goes low
                printf("s.array_data!\n");
                len=(((unsigned int)v[1])<<8) | ((unsigned int)v[2]);
                memcpy(buf, v, len*sizeof(char));
                buffer_valid=1;
                printf("s.array_data buffer_valid=%d, tosend=%d\n", buffer_valid, tosend);
                break;
        } // end select
    } // end while(1)

}

void
servo_handler(interface servo_data client cc)
{
    int i;
    timer t;
    unsigned int time;
    unsigned int period=0;
    unsigned int servo_width[8];
    unsigned int wait;

    unsigned int* movable swp=servo_width;

    for (i=0; i<8; i++)
    {
        swp[i]=1490;
    }
    wait=1*1E2; // 1*1E2 is 1usec
    t:>time;

    while(1)
    {
        select
        {
            case t when timerafter(time+wait) :> time: // 1*1E2 is 1usec
                for (i=0; i<8; i++)
                {
                    if (period==0)
                    {
                        servo_port[i] <: 1;
                        wait=1*1E2;
                    }
                    if (period==swp[i])
                    {
                        servo_port[i] <: 0;
                    }
                }
                period++;
                if (period>3000) // 3msec
                {
                    period=0;
                    wait=17*1E5; // 17 msec
                }
                break;
            case cc.data_ready():
                swp=cc.get_data(move(swp));
                printf("servo_handler [0] is now %d\n", swp[0]);
                break;
        } // end select
    } // end while
#ifdef junk
    int i;
    unsigned int t=0;
    unsigned int servo_width[8];

    for (i=0; i<8; i++)
    {
        configure_out_port(servo_port[i], clk, 0);
        servo_width[i]=1500;
    }
    set_clock_ref(clk);
    set_clock_div(clk, 50); // 1MHz
    start_clock(clk);

    while(1)
    {

        t+=1;   servo_port[i] @ t <: 0;
    }
#endif

}

void
data_handler(interface to_rpi client c,
             interface from_rpi server s,
             interface servo_data server ss)
{
    int tosend=0;
    int i;
    int idx;


    unsigned int servo_request[8];

    while(1)
    {
        select
        {

            case s.array_data(unsigned char* movable vp) -> unsigned char* movable vq:
                //printf("array message\n");
                if (vp[0]==0x02)  // servo update request
                {
                    idx=3;
                    for (i=0; i<8; i++)
                    {
                        servo_request[i]=(((unsigned int)vp[idx])<<8) | ((unsigned int)vp[idx+1]);
                        idx=idx+2;
                    }
                    printf("data_handler servo_request[0] is %d\n", servo_request[0]);
                    ss.data_ready(); // send notification to servo_handler
                }
                // we just send back this:
                vp[0]=0x55;
                vp[1]=0x00;
                vp[2]=0x01;
                vp[3]=0xaa;
                vq=move(vp);
                //tosend=1;   // uncomment this to send data back

                break;
            case s.code(unsigned char code):
                printf("code message\n");
                break;
            case ss.get_data(unsigned int* movable servop) -> unsigned int* movable servoq:
                for (i=0; i<8; i++)
                {
                    servop[i]=servo_request[i];
                }
                servoq=move(servop);
                break;
        } // end select
        if (tosend)
        {
            c.code(SEND);
            tosend=0;
        }
    } // end while(1)
}

int
main(void)
{
    interface to_rpi t;
    interface from_rpi f;
    interface servo_data v;

    ss_port :> void;



    par
    {
        spi_process(t, f);
        data_handler(t, f, v);
        servo_handler(v);
    }

    return(0);
}
