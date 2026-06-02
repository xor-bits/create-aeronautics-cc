local linalg = {}

function linalg.matrix_transpose(matrix)
  local src_h = #matrix
  local src_w = #matrix[1]

  local result = {}

  for i=1,src_w do
    result[i] = {}
    for j=1,src_h do
      result[i][j] = matrix[j][i]
    end
  end

  return result
end

function linalg.matrix_multiply(a, b)
  local a_h = #a
  local a_w = #a[1]
  local b_h = #b
  local b_w = #b[1]
  assert(a_w == b_h, "matrix multiplication size mismatch")

  local result = {}

  for j=1,a_h do
    result[j] = {}
    for i=1,b_w do
      local sum = 0.0
      for k=1,a_w do
        sum = sum + a[j][k] * b[k][i]
      end
      result[j][i] = sum
    end
  end

  return result
end

function linalg.matrix_inv2x2(matrix)
  local h = #matrix
  local w = #matrix[1]
  assert(h == 2)
  assert(w == 2)

  local c = 1.0 / (matrix[1][1] * matrix[2][2] - matrix[1][2] * matrix[2][1])
  return {
    { c * matrix[2][2], -c * matrix[1][2] },
    { -c * matrix[2][1], c * matrix[1][1] },
  }
end

return linalg
