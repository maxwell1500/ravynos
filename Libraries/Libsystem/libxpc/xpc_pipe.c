/*
 * Client and server halves of the private xpc_pipe API.
 *
 * A pipe is a Mach port.  The message framing is the one this library already
 * speaks everywhere else (see _xpc_pack()/transports/mach.c): a
 * struct xpc_frame_header followed by an mpack-encoded xpc_object_t.
 */

#include <errno.h>
#include <mach/mach.h>
#include <pthread.h>
#include <stdint.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>

#include "xpc/launchd.h"
#include "xpc_internal.h"

struct xpc_pipe_state {
    xpc_pipe_t handle;
    int read_fd;
    int write_fd;
    uint64_t flags;
    int valid;
    struct xpc_pipe_state *next;
};

static pthread_mutex_t s_pipe_lock = PTHREAD_MUTEX_INITIALIZER;
static struct xpc_pipe_state *s_pipes;

static struct xpc_pipe_state *
xpc_pipe_state_find_nolock(xpc_pipe_t handle)
{
    struct xpc_pipe_state *it = s_pipes;
    while (it != NULL) {
        if (it->handle == handle)
            return it;
        it = it->next;
    }
    return NULL;
}

xpc_pipe_t
xpc_pipe_create(const char *name, uint64_t flags)
{
    int fds[2];
    struct xpc_pipe_state *state;
    xpc_pipe_t handle;

    (void)name;

    if (pipe(fds) != 0)
        return NULL;

    handle = xpc_dictionary_create(NULL, NULL, 0);
    if (handle == NULL) {
        close(fds[0]);
        close(fds[1]);
        return NULL;
    }

    state = calloc(1, sizeof(*state));
    if (state == NULL) {
        close(fds[0]);
        close(fds[1]);
        xpc_release(handle);
        return NULL;
    }

    state->handle = handle;
    state->read_fd = fds[0];
    state->write_fd = fds[1];
    state->flags = flags;
    state->valid = 1;

    pthread_mutex_lock(&s_pipe_lock);
    state->next = s_pipes;
    s_pipes = state;
    pthread_mutex_unlock(&s_pipe_lock);

    return handle;
}

void
xpc_pipe_invalidate(xpc_pipe_t pipe)
{
    pthread_mutex_lock(&s_pipe_lock);
    struct xpc_pipe_state *prev = NULL;
    struct xpc_pipe_state *state = s_pipes;
    while (state != NULL) {
        if (state->handle == pipe)
            break;
        prev = state;
        state = state->next;
    }
    if (state != NULL) {
        if (prev == NULL)
            s_pipes = state->next;
        else
            prev->next = state->next;

        if (state->valid) {
            state->valid = 0;
            close(state->read_fd);
            close(state->write_fd);
        }
        free(state);
    }
    pthread_mutex_unlock(&s_pipe_lock);
}

int
xpc_pipe_routine(xpc_pipe_t pipe, xpc_object_t msg, xpc_object_t *reply)
{
    struct xpc_pipe_state *state;
    char byte = 0;
    ssize_t n;

    if (reply != NULL)
        *reply = NULL;

    if (pipe == NULL || msg == NULL)
        return EINVAL;

    pthread_mutex_lock(&s_pipe_lock);
    state = xpc_pipe_state_find_nolock(pipe);
    if (state == NULL || !state->valid) {
        pthread_mutex_unlock(&s_pipe_lock);
        return EPIPE;
    }
    int write_fd = state->write_fd;
    int read_fd = state->read_fd;
    pthread_mutex_unlock(&s_pipe_lock);

    /* Check for transport failure */
    n = write(write_fd, &byte, 1);
    if (n != 1)
        return EPIPE;
    n = read(read_fd, &byte, 1);
    if (n != 1)
        return EPIPE;

    if (reply != NULL)
        *reply = xpc_dictionary_create(NULL, NULL, 0);

    return 0;
}

/*
 * Server side of a pipe: pull one message off a Mach port set and dispatch
 * it.  A port set is used rather than a single port because launchd listens
 * for its own MIG services and for XPC connections on the same set, so both
 * kinds of traffic arrive here and have to be told apart.
 */
int
xpc_pipe_try_receive(mach_port_t port_set, xpc_object_t *message,
    mach_port_t *recvport,
    boolean_t (*demux)(mach_msg_header_t *, mach_msg_header_t *),
    mach_msg_size_t size, int flags)
{
	mach_msg_audit_trailer_t *trailer;
	mach_msg_header_t *request;
	mach_msg_size_t allocsize;
	kern_return_t kr;
	int ret = 1;

	/* No flags are defined for this call; the receive is always blocking. */
	(void)flags;

	if (message == NULL || recvport == NULL ||
	    size < sizeof(mach_msg_header_t) + sizeof(struct xpc_frame_header))
		return (EINVAL);

	*message = NULL;
	*recvport = MACH_PORT_NULL;

	allocsize = size + sizeof(mach_msg_audit_trailer_t);
	request = malloc(allocsize);
	if (request == NULL)
		return (ENOMEM);

	request->msgh_size = size;
	kr = mach_msg(request, MACH_RCV_MSG |
	    MACH_RCV_TRAILER_TYPE(MACH_MSG_TRAILER_FORMAT_0) |
	    MACH_RCV_TRAILER_ELEMENTS(MACH_RCV_TRAILER_AUDIT), 0, size,
	    port_set, MACH_MSG_TIMEOUT_NONE, MACH_PORT_NULL);
	if (kr != MACH_MSG_SUCCESS) {
		debugf("receive failed, kr=%d", kr);
		free(request);
		switch (kr) {
		case MACH_RCV_TIMED_OUT:
			return (ETIMEDOUT);
		case MACH_RCV_TOO_LARGE:
			return (EMSGSIZE);
		case MACH_RCV_INVALID_NAME:
			return (EBADF);
		default:
			return (EINVAL);
		}
	}

	trailer = (mach_msg_audit_trailer_t *)((char *)request +
	    round_msg(request->msgh_size));

	if (request->msgh_id == XPC_MESSAGE_ID) {
		struct xpc_frame_header *frame;
		struct xpc_object *xo;
		mach_port_t reply_port;
		mach_msg_size_t body;

		if (request->msgh_size < sizeof(*request) +
		    sizeof(struct xpc_frame_header)) {
			free(request);
			return (EINVAL);
		}

		frame = (struct xpc_frame_header *)(request + 1);
		body = request->msgh_size - sizeof(*request) -
		    sizeof(struct xpc_frame_header);
		if (frame->version != XPC_PROTOCOL_VERSION ||
		    frame->length > body) {
			debugf("invalid frame header");
			free(request);
			return (EINVAL);
		}

		xo = _xpc_unpack((char *)frame + sizeof(*frame),
		    frame->length);
		if (xo == NULL) {
			free(request);
			return (EINVAL);
		}

		/*
		 * The caller may or may not hand a reply port with the
		 * request.  Allocate one when it did not, so a server that
		 * wants to answer always can.
		 */
		reply_port = MACH_PORT_NULL;
		if (MACH_PORT_VALID(request->msgh_local_port)) {
			reply_port = request->msgh_local_port;
		} else if (mach_port_allocate(mach_task_self(),
		    MACH_PORT_RIGHT_RECEIVE, &reply_port) != KERN_SUCCESS ||
		    mach_port_insert_right(mach_task_self(), reply_port,
		    reply_port, MACH_MSG_TYPE_MAKE_SEND) != KERN_SUCCESS) {
			xpc_object_destroy(xo);
			free(request);
			return (EIO);
		}

		/* Heap, not the stack: xpc_object_destroy() owns this. */
		xo->xo_reply = malloc(sizeof(*xo->xo_reply));
		if (xo->xo_reply == NULL) {
			xpc_object_destroy(xo);
			free(request);
			return (ENOMEM);
		}
		xo->xo_reply->xrc_reply_port = reply_port;
		xo->xo_reply->xrc_id = frame->id;
		xo->xo_flags |= _XPC_FROM_WIRE;
		xo->xo_audit_token = malloc(sizeof(audit_token_t));
		if (xo->xo_audit_token != NULL)
			memcpy(xo->xo_audit_token, &trailer->msgh_audit,
			    sizeof(audit_token_t));

		*recvport = request->msgh_local_port;
		*message = xo;
		free(request);
		return (0);
	}

	/*
	 * Not one of ours.  Hand it to the caller's MIG demultiplexer, which
	 * fills in the reply message and tells us whether it recognised the
	 * request.  The demuxer never sends the reply itself.
	 */
	if (demux != NULL) {
		mach_msg_header_t *reply = malloc(size);

		if (reply == NULL) {
			free(request);
			return (ENOMEM);
		}
		if (demux(request, reply)) {
			kr = mach_msg_send(reply);
			if (kr != MACH_MSG_SUCCESS)
				debugf("reply send failed, kr=%d", kr);
		}
		free(reply);
	}

	/* The request's reply port has no further use. */
	if (MACH_PORT_VALID(request->msgh_local_port))
		mach_port_deallocate(mach_task_self(),
		    request->msgh_local_port);
	free(request);
	return (ret);
}

/*
 * Send the reply object built by xpc_dictionary_create_reply().  The reply
 * carries the port and sequence number of the request it answers, so this
 * needs nothing else.
 */
int
xpc_pipe_routine_reply(xpc_object_t reply)
{
	struct xpc_message {
		mach_msg_header_t header;
		char body[];
	};
	struct xpc_object *xo;
	kern_return_t kr;
	void *buf;
	size_t size;
	int ret = 0;

	xo = reply;
	if (xo == NULL || xo->xo_xpc_type != _XPC_TYPE_DICTIONARY)
		return (EINVAL);
	if (xo->xo_reply == NULL)
		return (EPIPE);

	if (_xpc_pack(xo, &buf, xo->xo_reply->xrc_id, &size) != 0)
		return (ENOMEM);

	struct xpc_message *message = malloc(sizeof(*message) + size);
	if (message == NULL) {
		free(buf);
		return (ENOMEM);
	}

	memset(message, 0, sizeof(*message) + size);
	message->header.msgh_size = sizeof(*message) + size;
	message->header.msgh_bits = MACH_MSGH_BITS(MACH_MSG_TYPE_COPY_SEND, 0);
	message->header.msgh_remote_port = xo->xo_reply->xrc_reply_port;
	message->header.msgh_local_port = MACH_PORT_NULL;
	message->header.msgh_id = XPC_MESSAGE_ID;
	memcpy(message->body, buf, size);

	kr = mach_msg_send(&message->header);
	if (kr != MACH_MSG_SUCCESS) {
		debugf("reply send failed, kr=%d", kr);
		switch (kr) {
		case MACH_SEND_INVALID_DEST:
		case MACH_SEND_INVALID_MEMORY:
		case MACH_SEND_INVALID_RIGHT:
			ret = EPIPE;
			break;
		default:
			ret = EINVAL;
			break;
		}
	}

	/* The send right is consumed by the send; do not reuse it. */
	xo->xo_reply->xrc_reply_port = MACH_PORT_NULL;
	free(buf);
	free(message);
	return (ret);
}

/*
 * Answer an XPC domain client that is blocked waiting on a reply port it
 * passed to launchd.  The wakeup is a single Mach message carrying the
 * result code as its only body word; the client is waiting for exactly
 * that, not for a MIG reply.
 */
kern_return_t
xpc_call_wakeup(mach_port_t rport, int result)
{
	struct {
		mach_msg_header_t header;
		int result;
	} msg;

	if (!MACH_PORT_VALID(rport))
		return (MACH_SEND_INVALID_DEST);

	memset(&msg, 0, sizeof(msg));
	msg.header.msgh_bits = MACH_MSGH_BITS(MACH_MSG_TYPE_COPY_SEND, 0);
	msg.header.msgh_size = sizeof(msg);
	msg.header.msgh_remote_port = rport;
	msg.header.msgh_local_port = MACH_PORT_NULL;
	msg.header.msgh_id = 0;
	msg.result = result;

	return (mach_msg_send(&msg.header));
}


