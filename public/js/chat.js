document.addEventListener('DOMContentLoaded', () => {
  console.log('fart')
  const chatForm = document.getElementById('chat-form');
  const chatBox = document.getElementById('chat-box');
  const chatInput = document.getElementById('chat-input');
  let accumulatingMessage = '';

  chatForm.addEventListener('submit', function(event) {
      event.preventDefault();
      const message = chatInput.value.trim();

      if (!message) {
        return;
      }
      
      chatForm.querySelector('button').disabled = true;

      addMessage('user');
      chatBox.lastElementChild.innerHTML = DOMPurify.sanitize(message);

      const highlightedCode = hljs.highlight(message, { language: 'plaintext' }).value
      console.log(highlightedCode)
      chatBox.lastElementChild.innerHTML = DOMPurify.sanitize(highlightedCode);

      chatInput.value = '';

      var formData = new FormData();
      formData.append('csrf_token', chatForm.querySelector('input[name="csrf_token"]').value);
      formData.append('message', message);

      var source = new SSE('/site_files/chat', {payload: formData, debug: false});

      source.addEventListener('message_start', function(e) {
        var payload = JSON.parse(e.data);
        addMessage('bot', '')
      });

      source.addEventListener('content_block_start', function(e) {
        var payload = JSON.parse(e.data);
      });

      source.addEventListener('content_block_delta', function(e) {
        var payload = JSON.parse(e.data);
        accumulatingMessage += payload.delta.text;
        const messageElement = chatBox.lastElementChild;
        messageElement.innerHTML = DOMPurify.sanitize(marked.parse(accumulatingMessage));
        messageElement.querySelectorAll('code').forEach((block) => {
          hljs.highlightElement(block);
        });
        
        scrollToBottom();
      });

      source.addEventListener('content_block_stop', function(e) {
        var payload = JSON.parse(e.data);
        const messageElement = chatBox.lastElementChild;
        // console.log(accumulatingMessage);
        accumulatingMessage = '';
        chatForm.querySelector('button').disabled = false;
      });
  });

  function addMessage(sender) {
      const messageElement = document.createElement('div');
      messageElement.classList.add('message', `${sender}-message`);
      chatBox.appendChild(messageElement);
      scrollToBottom();
  }

  
  // Keeps the chat box scrolled to the bottom

  function scrollToBottom() {
    chatBox.scrollTop = chatBox.scrollHeight;
  }

  window.onload = scrollToBottom;

  const observer = new MutationObserver(scrollToBottom);
  observer.observe(chatBox, { childList: true });

});