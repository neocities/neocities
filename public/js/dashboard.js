var dashboardViewType = localStorage && localStorage.getItem('viewType')

if(dashboardViewType != 'icon')
  $('#filesDisplay').addClass('list-view')

function confirmFileRename(path) {
  $('#renamePathInput').val(path);
  $('#renameNewPathInput').val(path);
  $('#renameModal').modal();
}

function confirmFileDelete(name) {
  resetDeleteConfirmModal();
  $('#deleteConfirmModal').data('delete-paths', [name]);
  $('#deleteFileName').text(name);
  $('#deleteFileCount').text('1');
  $('#deleteFileList').empty();
  $('#deleteSingleMessage').show();
  $('#deleteMultipleMessage').hide();
  $('#deleteConfirmModal').modal();
}

function setDeletePending(pending) {
  var modal = $('#deleteConfirmModal');
  var deleteButton = $('#deleteConfirmButton');
  var cancelButton = $('#deleteCancelButton');
  var closeButton = $('#deleteConfirmCloseButton');
  var paths = modal.data('delete-paths') || [];
  var deleteLabel = paths.length === 1 ? 'Deleting file...' : 'Deleting ' + paths.length + ' items...';

  modal.data('delete-pending', pending);
  deleteButton.prop('disabled', pending);
  cancelButton.prop('disabled', pending);
  closeButton.prop('disabled', pending);

  if (pending) {
    deleteButton.html('<i class="fa fa-spinner fa-spin"></i>Deleting...');
    $('#deleteProgressText').text(deleteLabel);
    $('#deleteProgressMessage').show();
  } else {
    deleteButton.html('<i class="fa fa-trash" title="Delete"></i>Delete');
    $('#deleteProgressMessage').hide();
  }
}

function resetDeleteConfirmModal() {
  setDeletePending(false);
}

function fileDelete() {
  var modal = $('#deleteConfirmModal');
  var paths = modal.data('delete-paths') || [$('#deleteFileName').text()];

  if (modal.data('delete-pending')) {
    return;
  }

  setDeletePending(true);

  $.ajax({
    url: '/api/delete',
    type: 'POST',
    data: {
      csrf_token: $('#deleteCSRFToken').val(),
      filenames: paths
    },
    success: function() {
      setDeletePending(false);
      modal.modal('hide');
      setBulkSelectMode(false);
      alertClear();
      alertType('success');

      if (paths.length === 1) {
        alertAdd($('<div>').text(paths[0]).html() + ' has been deleted.');
      } else {
        alertAdd(paths.length + ' items have been deleted.');
      }

      reloadDashboardFiles();
    },
    error: function(xhr) {
      var message = 'Failed to delete file(s).';

      try {
        message = JSON.parse(xhr.responseText).message || message;
      } catch(e) {
      }

      alertClear();
      alertType('error');
      alertAdd($('<div>').text(message).html());
      setDeletePending(false);
      modal.modal('hide');
    },
    complete: function() {
      setDeletePending(false);
    }
  });
}

function selectedFilePaths() {
  return $('.bulk-select-checkbox:checked').map(function() {
    return $(this).val();
  }).get();
}

function updateBulkActions() {
  var checkboxes = $('.bulk-select-checkbox');
  var checked = $('.bulk-select-checkbox:checked');
  var count = checked.length;
  var selectAll = $('#bulkSelectAll').get(0);

  $('#selectedFileCount').text(count);
  $('#bulkDeleteButton').prop('disabled', count === 0);

  checkboxes.each(function() {
    $(this).closest('.file').toggleClass('bulk-selected', $(this).prop('checked'));
  });

  if (selectAll) {
    selectAll.checked = count > 0 && count === checkboxes.length;
    selectAll.indeterminate = count > 0 && count < checkboxes.length;
  }
}

function setBulkSelectMode(enabled) {
  $('#filesDisplay').toggleClass('bulk-selecting', enabled);

  if (!enabled) {
    $('.bulk-select-checkbox').prop('checked', false);
  }

  updateBulkActions();
}

function toggleBulkSelect(event) {
  if (event) {
    event.preventDefault();
  }

  setBulkSelectMode(!$('#filesDisplay').hasClass('bulk-selecting'));
}

function clearFileSelection() {
  $('.bulk-select-checkbox').prop('checked', false);
  updateBulkActions();
}

function toggleSelectAllFiles(checked) {
  $('.bulk-select-checkbox').prop('checked', checked);
  updateBulkActions();
}

function confirmBulkDelete() {
  var paths = selectedFilePaths();

  if (paths.length === 0) {
    return;
  }

  resetDeleteConfirmModal();
  $('#deleteConfirmModal').data('delete-paths', paths);
  $('#deleteFileName').text(paths[0]);
  $('#deleteFileCount').text(paths.length);
  $('#deleteFileList').empty();

  paths.forEach(function(path) {
    $('<li>').text(path).appendTo('#deleteFileList');
  });

  $('#deleteSingleMessage').toggle(paths.length === 1);
  $('#deleteMultipleMessage').toggle(paths.length > 1);
  $('#deleteConfirmModal').modal();
}

$('#deleteConfirmModal').on('hide', function() {
  return !$(this).data('delete-pending');
});

function initBulkFileSelection() {
  $('.bulk-select-checkbox').off('change.bulk').on('change.bulk', updateBulkActions);

  $('.file').off('click.bulk').on('click.bulk', function(event) {
    if (!$('#filesDisplay').hasClass('bulk-selecting')) {
      return;
    }

    if ($(event.target).closest('a, button, label').length > 0) {
      return;
    }

    var checkbox = $(this).find('.bulk-select-checkbox');
    if (checkbox.length === 0) {
      return;
    }

    checkbox.prop('checked', !checkbox.prop('checked')).trigger('change');
    event.preventDefault();
  });

  updateBulkActions();
}

function clickUploadFiles() {
  $("input[id='uploadFiles']").click()
}

function showUploadProgress() {
  $('#uploadingOverlay').css('display', 'block')
}

function hideUploadProgress() {
  $('#progressBar').css('display', 'none')
  $('#uploadingOverlay').css('display', 'none')
}

$('#createDir').on('shown', function () {
  $('#newDirInput').focus();
})

$('#createFile').on('shown', function () {
  $('#newFileInput').focus();
  $('#newFileInput').val('');
  clearCreateFileError();
})

function showCreateFileError(message) {
  var errorDiv = $('#createFileError');
  errorDiv.text(message);
  errorDiv.show();
}

function clearCreateFileError() {
  var errorDiv = $('#createFileError');
  errorDiv.hide();
  errorDiv.text('');
}

function fileExists(filePath) {
  // Check if a file with this path already exists in the current file listing
  // Each file has a hidden div containing the file path
  var exists = false;
  var lowerFilePath = filePath.toLowerCase();
  
  $('#filesDisplay .file .overlay div[style*="display: none"]').each(function() {
    var existingPath = $(this).text().trim();
    if (existingPath.toLowerCase() === lowerFilePath) {
      exists = true;
      return false; // Break out of each loop
    }
  });
  
  return exists;
}

$('#newFileInput').on('keypress', function(e) {
  if (e.which === 13) { // Enter key
    handleCreateFile();
  }
})

function handleCreateFile() {
  if (createFileSubmitting) {
    return;
  }

  setCreateFileSubmitting(true);

  var filename = $('#newFileInput').val();
  var dir = $('#createFileDir').val();
  var csrfToken = $('#createFileCSRFToken').val();
  
  // Don't hide modal yet - wait for success or error
  createFileViaAPI(filename, dir, csrfToken);
}

function listView() {
  if(localStorage)
    localStorage.setItem('viewType', 'list')

  $('#filesDisplay').addClass('list-view')
}

function iconView() {
  if(localStorage)
    localStorage.setItem('viewType', 'icon')

  $('#filesDisplay').removeClass('list-view')
}

function alertAdd(text) {
  var a = $('#alertDialogue');
  a.css('display', 'block');
  a.append(text+'<br>');
}

function alertClear(){
  var a = $('#alertDialogue');
  a.css('display', 'none');
  a.text('');
}

function alertType(type){
  var a = $('#alertDialogue');
  a.removeClass('alert-success');
  a.removeClass('alert-error');
  a.addClass('alert-'+type);
}

var processedFiles = 0;
var uploadedFiles = 0;
var uploadedFileErrors = 0;
var createFileSubmitting = false;

function setCreateFileSubmitting(submitting) {
  createFileSubmitting = submitting;
  $('#createFileSubmitButton').prop('disabled', submitting);
}

function joinPaths(...paths) {
  return paths
    .map(path => path.replace(/(^\/|\/$)/g, ''))
    .filter(path => path !== '')
    .join('/');
}

function reInitDashboardFiles() {
  new Dropzone("#uploads", {
    url: "/api/upload",
    paramName: 'file',
    dictDefaultMessage: "",
    uploadMultiple: false,
    parallelUploads: 1,
    maxFilesize: 104857600, // 100MB
    clickable: document.getElementById('uploadButton'),
    init: function() {
      this.on("processing", function(file) {
        var dir = $('#uploads input[name="dir"]').val();
        if(file.fullPath) {
          this.options.paramName = joinPaths(dir,file.fullPath);
        } else {
          this.options.paramName = joinPaths(dir, file.name);
        }

        processedFiles++;
        $('#uploadFileName').text(this.options.paramName).prepend('<i class="icon-file"></i> ');
      });

      this.on("success", function(file) {
        uploadedFiles++;
      });

      this.on("error", function(file, message) {
        uploadedFiles++;
        uploadedFileErrors++;
        alertType('error');
        if (message && message.message) {
          alertAdd(message.message);
        } else {
          alertAdd(this.options.paramName+' failed to upload');
        }
      });

      this.on("queuecomplete", function() {
        hideUploadProgress();
        if(uploadedFileErrors > 0) {
          alertType('error');
          alertAdd(uploadedFiles-uploadedFileErrors+'/'+uploadedFiles+' files uploaded successfully');
        } else {
          alertType('success');
          alertAdd(uploadedFiles+' files uploaded successfully');
        }
        reloadDashboardFiles();
      });

      this.on("addedfiles", function(files) {
        uploadedFiles = 0;
        uploadedFileErrors = 0;
        alertClear();
        showUploadProgress();
      });
    }
  });

  document.getElementById('uploadButton').addEventListener('click', function(event) {
      event.preventDefault();
  });

  initBulkFileSelection();
}

function reloadDashboardFiles() {
  var dir = $('#uploads input[name="dir"]').val();
  var bulkSelecting = $('#filesDisplay').hasClass('bulk-selecting');
  $.get('/dashboard/files?dir='+encodeURIComponent(dir), function(data) {
    $('#filesDisplay').html(data);
    $('#filesDisplay').toggleClass('bulk-selecting', bulkSelecting);
    reInitDashboardFiles();
  });
}

function createFileViaAPI(filename, dir, csrfToken) {
  clearCreateFileError();
  showUploadProgress();
  
  filename = filename.replace(/[^a-zA-Z0-9_\-.]/g, '');
  
  if (!filename || filename.trim() === '') {
    hideUploadProgress();
    setCreateFileSubmitting(false);
    showCreateFileError('You must provide a file name.');
    return;
  }
  
  var extMatch = filename.match(/\.([^.]+)$/);

  // Check if extension is allowed for editing (if there is one)
  if (extMatch) {
    var extension = extMatch[1].toLowerCase();
    var validExtensions = [
      'html', 'htm', 'txt', 'js', 'css', 'scss', 'md', 'manifest', 'less', 
      'webmanifest', 'xml', 'json', 'opml', 'rdf', 'svg', 'gpg', 'pgp', 
      'resolvehandle', 'pls', 'yaml', 'yml', 'toml', 'osdx', 'mjs', 'cjs', 
      'ts', 'py', 'rss', 'glsl'
    ];
    
    if (validExtensions.indexOf(extension) === -1) {
      hideUploadProgress();
      setCreateFileSubmitting(false);
      showCreateFileError('Must be an editable file type (' + validExtensions.join(', ') + ') or a file with no extension.');
      return;
    }
  }
  // Files with no extension are allowed (they're treated as text files)
  
  var fullPath = dir ? joinPaths(dir, filename) : filename;
  
  // Check if file already exists
  if (fileExists(fullPath)) {
    hideUploadProgress();
    setCreateFileSubmitting(false);
    showCreateFileError('A file with this name already exists. Please choose a different name.');
    return;
  }
  
  var isHTML = /\.(html|htm)$/i.test(filename);
  
  // Create default HTML template content
  var htmlTemplate = '<!DOCTYPE html>\n' +
    '<html>\n' +
    '  <head>\n' +
    '    <meta charset="UTF-8">\n' +
    '    <meta name="viewport" content="width=device-width, initial-scale=1.0">\n' +
    '    <title>My Page</title>\n' +
    '    <link href="/style.css" rel="stylesheet" type="text/css" media="all">\n' +
    '  </head>\n' +
    '  <body>\n' +
    '  </body>\n' +
    '</html>';
  
  var content = isHTML ? htmlTemplate : '';
  
  // Create a blob with the content
  var blob = new Blob([content], { type: 'text/plain' });
  
  // Create FormData for the API upload
  var formData = new FormData();
  formData.append('csrf_token', csrfToken);
  formData.append(fullPath, blob, filename);
  
  $.ajax({
    url: '/api/upload',
    type: 'POST',
    data: formData,
    processData: false,
    contentType: false,
    success: function(response) {
      hideUploadProgress();
      setCreateFileSubmitting(false);
      alertClear();
      alertType('success');
      var escapedName = $('<div>').text(fullPath).html(); // HTML escape
      alertAdd(escapedName + ' was created! <a style="color: #FFFFFF; text-decoration: underline" href="/site_files/text_editor/' + encodeURIComponent(fullPath) + '">Click here to edit it</a>.');
      reloadDashboardFiles();
      $('#createFile').modal('hide'); // Hide modal on success
    },
    error: function(xhr) {
      hideUploadProgress();
      setCreateFileSubmitting(false);
      try {
        var errorData = JSON.parse(xhr.responseText);
        showCreateFileError(errorData.message || 'Failed to create file');
      } catch(e) {
        showCreateFileError('Failed to create file');
      }
    }
  });
}

// for first time load
reInitDashboardFiles();
